// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test, console, console2 } from "forge-std/Test.sol";
import { DeployEngine } from "../script/DeployEngine.s.sol";
import {
    BTtokensEngine_v1,
    OwnableUpgradeable,
    Initializable,
    BTtokenProxy,
    PausableUpgradeable
} from "../src/BTtokensEngine_v1.sol";
import { BTtokens_v1, AccessManagedUpgradeable, ERC20PermitUpgradeable } from "../src/BTtokens_v1.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { BTtokensManager } from "../src/BTtokensManager.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract BTtokens_v2 is BTtokens_v1 {
    /**
     * @dev Function that returns the version of the contract.
     * @return uint16 The version of the contract.
     */
    function getVersion() external pure virtual override returns (uint16) {
        return 2;
    }

    /**
     * @dev Function that authorizes the upgrade of the contract to a new implementation.     *
     * can authorize an upgrade to a new implementation contract.
     * @param _newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner whenNotEnginePaused { }
}

contract DeployAndUpgradeTest is Test {
    DeployEngine public engineDeployer;
    BTtokenProxy tokenProxy;

    BTtokens_v1 token;

    BTtokens_v2 newTokenImplementation = new BTtokens_v2();

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public accessManagerAddress;
    address public tokenAddress;
    bytes data;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");
    address tokenOwner = makeAddr("tokenOwner");

    address testAddress = makeAddr("testAddress");
    address testAddress2 = makeAddr("testAddress2");
    address testAddress3 = makeAddr("testAddress3");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint64 public constant AGENT = 10; // Roles are uint64 (0 is reserved for the ADMIN_ROLE)

    uint256 public constant AMOUNT = 1000;

    function setUp() public {
        engineDeployer = new DeployEngine();

        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin); //
        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();
        BTtokensEngine_v1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        tokenAddress = BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);

        token = BTtokens_v1(tokenAddress);
    }

    ////////////////////////////
    /// Initialization Tests ///
    ////////////////////////////

    function testCanNotInitializeWhenInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        BTtokens_v1(tokenAddress).initialize(data);
    }

    /// @dev tried to use modifiers instead of require statements and got this error: CompilerError: Stack too deep. Try
    /// compiling with `--via-ir` (cli) or the equivalent `viaIR: true` (standard JSON) while enabling the optimizer.
    /// Otherwise, try removing local variables.   --> src/BTtokens_v1.sol:148:24:

    function testCanNotInitializeWithEmptyName() public {
        string memory tokenName = "";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("invalid argument - empty string");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWithEmptySymbol() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "";
        address tokenManager = tokenManagerAddress;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("invalid argument - empty string");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWithInvalidDecimals() public {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = tokenManagerAddress;
        uint8 tokenDecimals = 19;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("decimals between 0 and 18");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWhenEngineIsZeroAddress() public {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = tokenManagerAddress;
        uint8 tokenDecimals = 6;

        data = abi.encode(address(0), tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("engine can not be address 0");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWhenTokenManagerIsZeroAddress() public {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = address(0);
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("token manager can not be address 0");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    ///////////////////////
    /// Variables Tests ///
    ///////////////////////

    function testTokenName() public {
        assertEq(token.name(), "BoulderTestToken");
    }

    function testTokenSymbol() public {
        assertEq(token.symbol(), "BTT");
    }

    function testTokenDecimals() public {
        assertEq(token.decimals(), 6);
    }

    function testTokenTotalSupply() public {
        assertEq(token.totalSupply(), 0);
    }

    function testTokenManager() public {
        assertEq(token.manager(), tokenManagerAddress);
    }

    function testTokenEngine() public {
        assertEq(token.engine(), engineProxy);
    }

    function testTokenOwner() public {
        assertEq(token.owner(), tokenOwner);
    }

    ////////////////////
    /// Supply Tests ///
    ////////////////////

    function testAgentCanMint() public {
        vm.startPrank(agent);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();

        assertEq(token.totalSupply(), AMOUNT);
    }

    function testEmitEventWhenMint() public {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit BTtokens_v1.TokensMinted(address(tokenAddress), address(testAddress), AMOUNT);

        vm.startPrank(agent);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();
    }

    function testUnauthorizedCanNotMint() public {
        vm.prank(testAddress);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, testAddress));
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();
    }

    function testAgentCanNotMintIfEnginePaused() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(agent);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();
    }

    function testAgentCanNotMintIfAccountBlacklisted() public {
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(agent);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();
    }

    function testAgentCanBurnIfBlacklisted() public {
        vm.startPrank(agent);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(agent);
        token.burn(testAddress, 500);
        vm.stopPrank();

        assertEq(token.totalSupply(), AMOUNT - 500);
    }

    function testEmitBurnEventIfAgentBurn() public {
        vm.startPrank(agent);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit BTtokens_v1.TokensBurned(address(tokenAddress), address(testAddress), 500);

        vm.startPrank(agent);
        token.burn(testAddress, 500);
        vm.stopPrank();
    }

    function testAgentCanNotBurnIfNotBlacklisted() public {
        vm.startPrank(agent);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();

        vm.startPrank(agent);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsNotBlacklisted.selector);
        token.burn(testAddress, 500);
        vm.stopPrank();

        assertEq(token.totalSupply(), AMOUNT);
    }

    /// @dev When doing this test _update has the modifier whenNotEnginePaused, so it reverts. Removed that modifier
    /// from the _update function to pass this test.
    function testAgentCanBurnIfBlacklistedAndEnginePaused() public {
        vm.startPrank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);
        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(agent);
        token.burn(testAddress, 500);
        vm.stopPrank();

        assertEq(token.totalSupply(), 500);
    }

    //////////////////////
    /// Transfer Tests ///
    //////////////////////

    modifier mintTokensToTestAddress() {
        vm.startPrank(agent);
        token.mint(testAddress, AMOUNT);
        vm.stopPrank();

        _;
    }

    function testCanApproveWhenRequirementsMet() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.allowance(testAddress, testAddress2), AMOUNT);
    }

    function testEmitEventWhenApproved() public mintTokensToTestAddress {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit BTtokens_v1.TokensApproved(address(tokenAddress), address(testAddress), address(testAddress2), AMOUNT);

        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();
    }

    function testCanNotApproveIfEnginePaused() public mintTokensToTestAddress {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.allowance(testAddress, testAddress2), 0);
    }

    function testCanNotApproveIfSenderBlacklisted() public mintTokensToTestAddress {
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.allowance(testAddress, testAddress2), 0);
    }

    function testCanNotApproveIfSpenderIsBlacklisted() public mintTokensToTestAddress {
        BTtokensEngine_v1(engineProxy).blacklist(testAddress2);

        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.allowance(testAddress, testAddress2), 0);
    }

    function testCanTransferFromIfRequirementsMet() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        vm.startPrank(testAddress2);
        token.transferFrom(testAddress, testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), 0);
        assertEq(token.balanceOf(testAddress2), AMOUNT);
    }

    function testEmitEventIfCanTransferFrom() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit BTtokens_v1.TransferFrom(address(tokenAddress), testAddress, testAddress, testAddress2, AMOUNT);

        vm.startPrank(testAddress2);
        token.transferFrom(testAddress, testAddress2, AMOUNT);
        vm.stopPrank();
    }

    function testCanNotTransferFromIfENginePaused() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(testAddress2);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.transferFrom(testAddress, testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
    }

    function testCanNotTransferFromIfSenderBlacklisted() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress2);

        vm.startPrank(testAddress2);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transferFrom(testAddress, testAddress3, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
    }

    function testCanNotTransferFromIfPayerBlacklisted() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(testAddress2);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transferFrom(testAddress, testAddress3, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
    }

    function testCanNotTransferFromIfPayeeBlacklisted() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.approve(testAddress2, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress3);

        vm.startPrank(testAddress2);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transferFrom(testAddress, testAddress3, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
    }

    function testCanTransferIfRequirementsMet() public mintTokensToTestAddress {
        vm.startPrank(testAddress);
        token.transfer(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), 0);
        assertEq(token.balanceOf(testAddress2), AMOUNT);
    }

    function testEmitEventIfCanTransfer() public mintTokensToTestAddress {
        vm.expectEmit(true, false, true, true, address(tokenAddress));
        emit BTtokens_v1.TokenTransfer(address(tokenAddress), testAddress, testAddress2, AMOUNT);

        vm.startPrank(testAddress);
        token.transfer(testAddress2, AMOUNT);
        vm.stopPrank();
    }

    function testCanNotTransferIfEnginePaused() public mintTokensToTestAddress {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.transfer(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
    }

    function testCanNotTransferIfSenderBlacklisted() public mintTokensToTestAddress {
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transfer(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
    }

    function testCanNotTransferIfReceiverBlacklisted() public mintTokensToTestAddress {
        BTtokensEngine_v1(engineProxy).blacklist(testAddress2);

        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transfer(testAddress2, AMOUNT);
        vm.stopPrank();

        assertEq(token.balanceOf(testAddress), AMOUNT);
        assertEq(token.balanceOf(testAddress2), 0);
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
        uint256 nonce = token.nonces(owner);
        bytes32 DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();

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
        /// @dev // `makeAddr(...)` generates a pseudo-random address that can't be used for ECDSA signing (no known
        /// private key)
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1); // 1 = owner PK

        vm.prank(spender);
        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
        assertEq(token.nonces(owner), 1);
    }

    function testPermitFailsWithExpiredSignature() public mintTokensToTestAddress {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp - 1; // Expired

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1); // 1 = owner PK

        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, deadline));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitFailsWithInvalidSignature() public mintTokensToTestAddress {
        address owner = vm.addr(1); // Esta es la address esperada
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        /// @dev sign with incorrect private key (pk = 2)
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 2);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20PermitUpgradeable.ERC2612InvalidSigner.selector,
                vm.addr(2), // signer's address (from pk = 2)
                owner // expected owner
            )
        );
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitAndTransferFromFlow() public {
        address owner = vm.addr(1); // Signer
        address spender = testAddress2; // Spender (transferFrom caller)
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        // Mint tokens to owner
        vm.prank(agent);
        token.mint(owner, value);

        // Check that spender doesn't have allowance initially
        assertEq(token.allowance(owner, spender), 0);

        // Sing permit off-chain
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        // Spender does permit + transferFrom in 2 txs
        vm.prank(spender);
        token.permit(owner, spender, value, deadline, v, r, s);

        vm.prank(spender);
        token.transferFrom(owner, spender, value);

        // Verificamos que los fondos fueron transferidos correctamente
        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(spender), value);
    }

    function testPermitAndTransferSingleCall() public {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        // Mint tokens to owner
        vm.prank(agent);
        token.mint(owner, value);

        // Permit sign
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        // spender does all in one tx
        vm.prank(spender);
        token.permitAndTransfer(owner, spender, value, deadline, v, r, s);

        assertEq(token.balanceOf(owner), 0);
        assertEq(token.balanceOf(spender), value);
    }

    function testPermitAndTransferFailsIfEnginePaused() public {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        // Mint tokens
        vm.prank(agent);
        token.mint(owner, value);

        // Pause engine
        BTtokensEngine_v1(engineProxy).pauseEngine();

        // Valid signature
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    function testPermitAndTransferFailsIfOwnerBlacklisted() public {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(agent);
        token.mint(owner, value);

        // Blacklist owner
        BTtokensEngine_v1(engineProxy).blacklist(owner);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    function testPermitAndTransferFailsIfSpenderBlacklisted() public {
        address owner = vm.addr(1);
        address spender = testAddress2;
        uint256 value = AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        vm.prank(agent);
        token.mint(owner, value);

        // Blacklist spender
        BTtokensEngine_v1(engineProxy).blacklist(spender);

        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(owner, spender, value, deadline, 1);

        vm.prank(spender);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.permitAndTransfer(owner, spender, value, deadline, v, r, s);
    }

    /////////////////////
    /// Upgrade Tests ///
    /////////////////////

    function testUpgradeTokens() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();
        /// @dev this contract is the owner, that's why the engine stops

        vm.startPrank(tokenOwner);
        /// @dev tokenOwner is the token owner

        BTtokens_v1(tokenAddress).upgradeToAndCall(address(newTokenImplementation), "");

        vm.stopPrank();

        assertEq(BTtokens_v2(tokenAddress).getVersion(), 2);
    }

    function testUpgradeFailIfEngineNotPaused() public {
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsNotPaused.selector);
        vm.startPrank(tokenOwner);
        BTtokens_v1(tokenAddress).upgradeToAndCall(address(newTokenImplementation), "");
        vm.stopPrank();
    }

    function testUpgradeFailIfUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, testAddress));
        vm.startPrank(testAddress);
        BTtokens_v1(tokenAddress).upgradeToAndCall(address(newTokenImplementation), "");
        vm.stopPrank();
    }

    function testTokenVariablesRemainsIfUpgrade() public {
        vm.startPrank(agent);
        BTtokens_v1(tokenAddress).mint(testAddress, AMOUNT);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).pauseEngine();

        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(address(newTokenImplementation));

        /// @dev only for robusteness testing, it should be firstly changed on the engine and then used on the token
        address newImplementationToken = BTtokensEngine_v1(engineProxy).s_tokenImplementationAddress();

        vm.startPrank(tokenOwner);
        BTtokens_v1(tokenAddress).upgradeToAndCall(address(newImplementationToken), "");
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).unPauseEngine();

        assertEq(BTtokens_v2(tokenAddress).name(), "BoulderTestToken");
        assertEq(BTtokens_v2(tokenAddress).symbol(), "BTT");
        assertEq(BTtokens_v2(tokenAddress).decimals(), 6);
        assertEq(BTtokens_v2(tokenAddress).totalSupply(), AMOUNT);
        assertEq(BTtokens_v2(tokenAddress).manager(), tokenManagerAddress);
        assertEq(BTtokens_v2(tokenAddress).engine(), engineProxy);
        assertEq(BTtokens_v2(tokenAddress).owner(), tokenOwner);
        assertEq(BTtokens_v2(tokenAddress).getVersion(), 2);
        assertEq(BTtokens_v2(tokenAddress).balanceOf(testAddress), AMOUNT);
    }
}
