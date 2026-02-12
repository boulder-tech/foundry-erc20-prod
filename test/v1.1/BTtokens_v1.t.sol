// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { DeployEngine } from "../../script/DeployEngine.s.sol";
import { BTtokensEngine_v1 as EngineV1_0 } from "../../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokensEngine_v1 as EngineV1_1 } from "../../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { BTtokens_v1 as TokenV1_0 } from "../../src/BTContracts/v1.0/BTtokens_v1.sol";
import { BTtokens_v1 as TokenV1_1 } from "../../src/BTContracts/v1.1/BTtokens_v1.sol";
import { BTtokensManager } from "../../src/BTContracts/v1.0/BTtokensManager.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20PermitUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

contract BTtokens_v2 is TokenV1_1 {
    function getVersion() external pure virtual override returns (string memory) {
        return "2.0";
    }

    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner whenEnginePaused { }
}

/**
 * @title Tests for BTtokens_v1 (token) in v1.1.
 * @notice Engine tests live in BTtokensEngine_v1.t.sol; upgrade flow in UpgradeV1_0_to_V1_1.t.sol.
 *         Here: v1.1 token behavior (mint, burn, transfer, permit, setAccessManager, upgrade, etc.).
 */
contract BTtokensV1_1Test is Test {
    DeployEngine public engineDeployer;
    EngineV1_1 public engineV1_1Impl;
    TokenV1_1 public tokenV1_1Impl;
    BTtokens_v2 public tokenV2Impl;

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public tokenAddress;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");
    address tokenOwner = makeAddr("tokenOwner");
    address tokenHolder = makeAddr("tokenHolder");

    address testAddress = makeAddr("testAddress");
    address testAddress2 = makeAddr("testAddress2");
    address testAddress3 = makeAddr("testAddress3");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint64 public constant AGENT = 10;

    string constant TOKEN_NAME = "BoulderTestToken";
    string constant TOKEN_SYMBOL = "BTT";
    uint8 constant TOKEN_DECIMALS = 6;
    uint256 public constant AMOUNT = 1000;

    modifier asAgent() {
        vm.startPrank(agent);
        _;
        vm.stopPrank();
    }

    modifier asTestAddress() {
        vm.startPrank(testAddress);
        _;
        vm.stopPrank();
    }

    modifier asTestAddress2() {
        vm.startPrank(testAddress2);
        _;
        vm.stopPrank();
    }

    modifier withEnginePaused() {
        EngineV1_1(engineProxy).pauseEngine();
        _;
    }

    modifier withAccountBlacklisted(address account) {
        EngineV1_1(engineProxy).blacklist(account);
        _;
    }

    modifier withApproval() {
        vm.startPrank(testAddress);
        TokenV1_1(tokenAddress).approve(testAddress2, AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier mintToOwner(address owner, uint256 amount) {
        vm.prank(agent);
        TokenV1_1(tokenAddress).mint(owner, amount);
        _;
    }

    function setUp() public {
        engineDeployer = new DeployEngine();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin);

        vm.startPrank(initialAdmin);
        BTtokensManager(tokenManagerAddress).grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();

        EngineV1_0(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        bytes memory data = abi.encode(
            engineProxy,
            tokenManagerAddress,
            tokenOwner,
            tokenHolder,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        tokenAddress = EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, tokenOwner);

        engineV1_1Impl = new EngineV1_1();
        tokenV1_1Impl = new TokenV1_1();
        tokenV2Impl = new BTtokens_v2();

        vm.startPrank(address(this));
        EngineV1_0(engineProxy).pauseEngine();
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Impl), "");
        EngineV1_0(engineProxy).unPauseEngine();
        vm.stopPrank();

        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        vm.stopPrank();
        vm.prank(tokenOwner);
        TokenV1_0(tokenAddress).upgradeToAndCall(address(tokenV1_1Impl), "");
        vm.prank(address(this));
        EngineV1_1(engineProxy).unPauseEngine();
    }

    ///////////////////////
    /// Variables Tests ///
    ///////////////////////

    function test_TokenIsV1_1() public {
        assertEq(TokenV1_1(tokenAddress).getVersion(), "1.1");
        assertEq(TokenV1_1(tokenAddress).name(), TOKEN_NAME);
        assertEq(TokenV1_1(tokenAddress).symbol(), TOKEN_SYMBOL);
        assertEq(TokenV1_1(tokenAddress).decimals(), TOKEN_DECIMALS);
        assertEq(TokenV1_1(tokenAddress).s_manager(), tokenManagerAddress);
    }

    function testTokenName() public {
        assertEq(TokenV1_1(tokenAddress).name(), TOKEN_NAME);
    }

    function testTokenSymbol() public {
        assertEq(TokenV1_1(tokenAddress).symbol(), TOKEN_SYMBOL);
    }

    function testTokenDecimals() public {
        assertEq(TokenV1_1(tokenAddress).decimals(), TOKEN_DECIMALS);
    }

    function testTokenTotalSupply() public {
        assertEq(TokenV1_1(tokenAddress).totalSupply(), 0);
    }

    function testTokenManager() public {
        assertEq(TokenV1_1(tokenAddress).manager(), tokenManagerAddress);
    }

    function testTokenEngine() public {
        assertEq(TokenV1_1(tokenAddress).engine(), engineProxy);
    }

    function testTokenOwner() public {
        assertEq(TokenV1_1(tokenAddress).owner(), tokenOwner);
    }

    function testTokenHolder() public {
        assertEq(TokenV1_1(tokenAddress).s_token_holder(), tokenHolder);
    }

    function testTokenInitialized() public {
        assertTrue(TokenV1_1(tokenAddress).initialized());
    }

    /////////////////////
    /// Setters Tests ///
    /////////////////////

    function testSetTokenHolder() public {
        address newHolder = makeAddr("newHolder");
        vm.prank(tokenOwner);
        TokenV1_1(tokenAddress).setTokenHolder(newHolder);
        assertEq(TokenV1_1(tokenAddress).s_token_holder(), newHolder);
    }

    function testSetTokenHolderRevertsIfZeroAddress() public {
        vm.prank(tokenOwner);
        vm.expectRevert(TokenV1_1.BTtokens__AddressCanNotBeZero.selector);
        TokenV1_1(tokenAddress).setTokenHolder(address(0));
    }

    function testSetTokenHolderFailsIfNotOwner() public {
        vm.prank(testAddress);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, testAddress));
        TokenV1_1(tokenAddress).setTokenHolder(testAddress);
    }

    function testSetNameAndSymbol() public {
        string memory newName = "NewTokenName";
        string memory newSymbol = "NTK";
        vm.prank(engineProxy);
        TokenV1_1(tokenAddress).setNameAndSymbol(newName, newSymbol);
        assertEq(TokenV1_1(tokenAddress).name(), newName);
        assertEq(TokenV1_1(tokenAddress).symbol(), newSymbol);
    }

    function testSetNameAndSymbolFailsIfNotEngine() public {
        vm.prank(tokenOwner);
        vm.expectRevert(TokenV1_1.BTtokens__OnlyEngineCanCall.selector);
        TokenV1_1(tokenAddress).setNameAndSymbol("NewName", "NS");
    }

    function testSetNameAndSymbolFailsIfEmptyString() public {
        vm.prank(engineProxy);
        vm.expectRevert(TokenV1_1.BTtokens__StringCanNotBeEmpty.selector);
        TokenV1_1(tokenAddress).setNameAndSymbol("", TOKEN_SYMBOL);

        vm.prank(engineProxy);
        vm.expectRevert(TokenV1_1.BTtokens__StringCanNotBeEmpty.selector);
        TokenV1_1(tokenAddress).setNameAndSymbol(TOKEN_NAME, "");
    }

    function testSetAccessManager() public {
        BTtokensManager newManager = new BTtokensManager(initialAdmin);
        vm.prank(initialAdmin);
        newManager.grantRole(ADMIN_ROLE, address(engineProxy), 0);

        vm.prank(engineProxy);
        TokenV1_1(tokenAddress).setAccessManager(address(newManager));

        assertEq(TokenV1_1(tokenAddress).s_manager(), address(newManager));
        assertEq(TokenV1_1(tokenAddress).manager(), address(newManager));
    }

    function testSetAccessManagerFailsIfNotEngine() public {
        BTtokensManager newManager = new BTtokensManager(initialAdmin);
        vm.prank(tokenOwner);
        vm.expectRevert(TokenV1_1.BTtokens__OnlyEngineCanCall.selector);
        TokenV1_1(tokenAddress).setAccessManager(address(newManager));
    }

    function testSetAccessManagerFailsIfZeroAddress() public {
        vm.prank(engineProxy);
        vm.expectRevert(TokenV1_1.BTtokens__AddressCanNotBeZero.selector);
        TokenV1_1(tokenAddress).setAccessManager(address(0));
    }

    ////////////////////
    /// Supply Tests ///
    ////////////////////

    modifier mintTokensToTestAddress() {
        vm.startPrank(agent);
        TokenV1_1(tokenAddress).mint(testAddress, AMOUNT);
        vm.stopPrank();
        _;
    }

    function testAgentCanMint() public asAgent {
        TokenV1_1(tokenAddress).mint(testAddress, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).totalSupply(), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
    }

    function testEmitEventWhenMint() public {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit TokenV1_1.TokensMinted(address(tokenAddress), testAddress, AMOUNT);

        vm.startPrank(agent);
        TokenV1_1(tokenAddress).mint(testAddress, AMOUNT);
        vm.stopPrank();
    }

    function testUnauthorizedCanNotMint() public {
        vm.prank(testAddress);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, testAddress));
        TokenV1_1(tokenAddress).mint(testAddress, AMOUNT);
    }

    function testAgentCanNotMintIfEnginePaused() public withEnginePaused asAgent {
        vm.expectRevert(TokenV1_1.BTtokens__EngineIsPaused.selector);
        TokenV1_1(tokenAddress).mint(testAddress, AMOUNT);
    }

    function testAgentCanNotMintIfAccountBlacklisted() public withAccountBlacklisted(testAddress) asAgent {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).mint(testAddress, AMOUNT);
    }

    function testAgentCanBurnIfBlacklisted() public mintTokensToTestAddress withAccountBlacklisted(testAddress) asAgent {
        TokenV1_1(tokenAddress).burn(testAddress, 500);
        assertEq(TokenV1_1(tokenAddress).totalSupply(), AMOUNT - 500);
    }

    function testEmitBurnEventIfAgentBurn() public mintTokensToTestAddress withAccountBlacklisted(testAddress) {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit TokenV1_1.TokensBurned(address(tokenAddress), testAddress, 500);

        vm.startPrank(agent);
        TokenV1_1(tokenAddress).burn(testAddress, 500);
        vm.stopPrank();
    }

    function testAgentCanNotBurnIfNotBlacklisted() public mintTokensToTestAddress asAgent {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsNotBlacklisted.selector);
        TokenV1_1(tokenAddress).burn(testAddress, 500);
        assertEq(TokenV1_1(tokenAddress).totalSupply(), AMOUNT);
    }

    function testAgentCanBurnIfTokenHolder() public asAgent {
        TokenV1_1(tokenAddress).mint(tokenHolder, AMOUNT);
        TokenV1_1(tokenAddress).burn(tokenHolder, 500);
        assertEq(TokenV1_1(tokenAddress).totalSupply(), AMOUNT - 500);
    }

    //////////////////////
    /// Transfer Tests ///
    //////////////////////

    function testCanApproveWhenRequirementsMet() public mintTokensToTestAddress asTestAddress {
        TokenV1_1(tokenAddress).approve(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).allowance(testAddress, testAddress2), AMOUNT);
    }

    function testEmitEventWhenApproved() public mintTokensToTestAddress {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit TokenV1_1.TokensApproved(address(tokenAddress), testAddress, testAddress2, AMOUNT);

        vm.startPrank(testAddress);
        TokenV1_1(tokenAddress).approve(testAddress2, AMOUNT);
        vm.stopPrank();
    }

    function testCanNotApproveIfEnginePaused() public mintTokensToTestAddress withEnginePaused asTestAddress {
        vm.expectRevert(TokenV1_1.BTtokens__EngineIsPaused.selector);
        TokenV1_1(tokenAddress).approve(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).allowance(testAddress, testAddress2), 0);
    }

    function testCanNotApproveIfSenderBlacklisted() public mintTokensToTestAddress withAccountBlacklisted(testAddress) asTestAddress {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).approve(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).allowance(testAddress, testAddress2), 0);
    }

    function testCanNotApproveIfSpenderIsBlacklisted() public mintTokensToTestAddress withAccountBlacklisted(testAddress2) asTestAddress {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).approve(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).allowance(testAddress, testAddress2), 0);
    }

    function testCanTransferFromIfRequirementsMet() public mintTokensToTestAddress withApproval asTestAddress2 {
        TokenV1_1(tokenAddress).transferFrom(testAddress, testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), 0);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), AMOUNT);
    }

    function testEmitEventIfCanTransferFrom() public mintTokensToTestAddress withApproval {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit TokenV1_1.TransferFrom(address(tokenAddress), testAddress2, testAddress, testAddress2, AMOUNT);

        vm.startPrank(testAddress2);
        TokenV1_1(tokenAddress).transferFrom(testAddress, testAddress2, AMOUNT);
        vm.stopPrank();
    }

    function testCanNotTransferFromIfEnginePaused() public mintTokensToTestAddress withApproval withEnginePaused asTestAddress2 {
        vm.expectRevert(TokenV1_1.BTtokens__EngineIsPaused.selector);
        TokenV1_1(tokenAddress).transferFrom(testAddress, testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    function testCanNotTransferFromIfSenderBlacklisted() public mintTokensToTestAddress withApproval withAccountBlacklisted(testAddress2) asTestAddress2 {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).transferFrom(testAddress, testAddress3, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    function testCanNotTransferFromIfPayerBlacklisted() public mintTokensToTestAddress withApproval withAccountBlacklisted(testAddress) asTestAddress2 {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).transferFrom(testAddress, testAddress3, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    function testCanNotTransferFromIfPayeeBlacklisted() public mintTokensToTestAddress withApproval withAccountBlacklisted(testAddress3) asTestAddress2 {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).transferFrom(testAddress, testAddress3, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    function testCanTransferIfRequirementsMet() public mintTokensToTestAddress asTestAddress {
        TokenV1_1(tokenAddress).transfer(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), 0);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), AMOUNT);
    }

    function testEmitEventIfCanTransfer() public mintTokensToTestAddress {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit TokenV1_1.TokenTransfer(address(tokenAddress), testAddress, testAddress2, AMOUNT);

        vm.startPrank(testAddress);
        TokenV1_1(tokenAddress).transfer(testAddress2, AMOUNT);
        vm.stopPrank();
    }

    function testCanNotTransferIfEnginePaused() public mintTokensToTestAddress withEnginePaused asTestAddress {
        vm.expectRevert(TokenV1_1.BTtokens__EngineIsPaused.selector);
        TokenV1_1(tokenAddress).transfer(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    function testCanNotTransferIfSenderBlacklisted() public mintTokensToTestAddress withAccountBlacklisted(testAddress) asTestAddress {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).transfer(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    function testCanNotTransferIfReceiverBlacklisted() public mintTokensToTestAddress withAccountBlacklisted(testAddress2) asTestAddress {
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).transfer(testAddress2, AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress), AMOUNT);
        assertEq(TokenV1_1(tokenAddress).balanceOf(testAddress2), 0);
    }

    ////////////////////
    /// Permit Tests ///
    ////////////////////

    function getPermitSignature(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 ownerPrivateKey
    )
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        uint256 nonce = TokenV1_1(tokenAddress).nonces(owner);
        bytes32 DOMAIN_SEPARATOR = TokenV1_1(tokenAddress).DOMAIN_SEPARATOR();

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        return vm.sign(ownerPrivateKey, digest);
    }

    function testPermitSetsAllowanceCorrectly() public mintTokensToTestAddress {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        TokenV1_1(tokenAddress).permit(owner, spender, value, deadline, v, r, s);

        assertEq(TokenV1_1(tokenAddress).allowance(owner, spender), value);
        assertEq(TokenV1_1(tokenAddress).nonces(owner), 1);
    }

    function testPermitFailsWithExpiredSignature() public mintTokensToTestAddress {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
        TokenV1_1(tokenAddress).permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitFailsWithInvalidSignature() public mintTokensToTestAddress {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 2);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20PermitUpgradeable.ERC2612InvalidSigner.selector,
                vm.addr(2),
                owner
            )
        );
        TokenV1_1(tokenAddress).permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitAndTransferFromFlow() public mintToOwner(vm.addr(1), AMOUNT) {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        assertEq(TokenV1_1(tokenAddress).allowance(owner, spender), 0);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        TokenV1_1(tokenAddress).permit(owner, spender, value, deadline, v, r, s);

        vm.prank(spender);
        TokenV1_1(tokenAddress).transferFrom(owner, spender, value);

        assertEq(TokenV1_1(tokenAddress).balanceOf(owner), 0);
        assertEq(TokenV1_1(tokenAddress).balanceOf(spender), value);
    }

    function testPermitAndTransferSingleCall() public mintToOwner(vm.addr(1), AMOUNT) {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        TokenV1_1(tokenAddress).permitAndTransfer(owner, spender, value, deadline, v, r, s);

        assertEq(TokenV1_1(tokenAddress).balanceOf(owner), 0);
        assertEq(TokenV1_1(tokenAddress).balanceOf(spender), value);
    }

    function testPermitAndTransferFailsIfEnginePaused() public mintToOwner(vm.addr(1), AMOUNT) withEnginePaused {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(TokenV1_1.BTtokens__EngineIsPaused.selector);
        TokenV1_1(tokenAddress).permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    function testPermitAndTransferFailsIfOwnerBlacklisted() public mintToOwner(vm.addr(1), AMOUNT) withAccountBlacklisted(vm.addr(1)) {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    function testPermitAndTransferFailsIfSpenderBlacklisted() public mintToOwner(vm.addr(1), AMOUNT) withAccountBlacklisted(testAddress2) {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(TokenV1_1.BTtokens__AccountIsBlacklisted.selector);
        TokenV1_1(tokenAddress).permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    function testEmitEventPermitAndTransfer() public mintToOwner(vm.addr(1), AMOUNT) {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.expectEmit(true, true, true, true, address(tokenAddress));
        emit TokenV1_1.PermitAndTransfer(address(tokenAddress), spender, owner, spender, value, deadline);

        vm.prank(spender);
        TokenV1_1(tokenAddress).permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    /////////////////////
    /// Upgrade Tests ///
    /////////////////////

    function testUpgradeTokens() public withEnginePaused {
        vm.startPrank(tokenOwner);
        TokenV1_1(tokenAddress).upgradeToAndCall(address(tokenV2Impl), "");
        vm.stopPrank();

        assertEq(BTtokens_v2(tokenAddress).getVersion(), "2.0");
    }

    function testUpgradeFailIfEngineNotPaused() public {
        vm.expectRevert(TokenV1_1.BTtokens__EngineIsNotPaused.selector);
        vm.startPrank(tokenOwner);
        TokenV1_1(tokenAddress).upgradeToAndCall(address(tokenV2Impl), "");
        vm.stopPrank();
    }

    function testUpgradeFailIfUnauthorized() public withEnginePaused {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, testAddress));
        vm.startPrank(testAddress);
        TokenV1_1(tokenAddress).upgradeToAndCall(address(tokenV2Impl), "");
        vm.stopPrank();
    }

    function testTokenVariablesRemainsIfUpgrade() public mintTokensToTestAddress withEnginePaused {
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(address(tokenV2Impl));

        address newImplementationToken = EngineV1_1(engineProxy).s_tokenImplementationAddress();

        vm.startPrank(tokenOwner);
        TokenV1_1(tokenAddress).upgradeToAndCall(address(newImplementationToken), "");
        vm.stopPrank();

        EngineV1_1(engineProxy).unPauseEngine();

        assertEq(BTtokens_v2(tokenAddress).name(), TOKEN_NAME);
        assertEq(BTtokens_v2(tokenAddress).symbol(), TOKEN_SYMBOL);
        assertEq(BTtokens_v2(tokenAddress).decimals(), TOKEN_DECIMALS);
        assertEq(BTtokens_v2(tokenAddress).totalSupply(), AMOUNT);
        assertEq(BTtokens_v2(tokenAddress).manager(), tokenManagerAddress);
        assertEq(BTtokens_v2(tokenAddress).engine(), engineProxy);
        assertEq(BTtokens_v2(tokenAddress).owner(), tokenOwner);
        assertEq(BTtokens_v2(tokenAddress).getVersion(), "2.0");
        assertEq(BTtokens_v2(tokenAddress).balanceOf(testAddress), AMOUNT);
    }
}
