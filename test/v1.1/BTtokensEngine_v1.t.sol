// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console, console2 } from "forge-std/Test.sol";
import { DeployEngine } from "../../script/DeployEngine.s.sol";
import {
    BTtokensEngine_v1 as EngineV1_1,
    OwnableUpgradeable,
    Initializable,
    BTtokenProxy,
    PausableUpgradeable
} from "../../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { BTtokens_v1, AccessManagedUpgradeable } from "../../src/BTContracts/v1.1/BTtokens_v1.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { BTtokensManager } from "../../src/BTContracts/v1.1/BTtokensManager.sol";

contract BTtokensEngine_v2 is EngineV1_1 {
    /**
     * @dev Function that returns the version of the contract.
     * @return string memory The version of the contract.
     */
    function getVersion() external pure virtual override returns (string memory) {
        return "2.0";
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

    /// @dev v1.1 implementation used in setUp so all tests run against engine v1.1
    EngineV1_1 newEngineImplementation = new EngineV1_1();
    /// @dev v1.1 token implementation so createToken deploys v1.1 tokens (required for changeTokenAccessManager)
    BTtokens_v1 public tokenV1_1Implementation;
    /// @dev v2 test double used only in upgrade tests to verify upgrade path (getVersion "2.0")
    BTtokensEngine_v2 v2EngineImplementation = new BTtokensEngine_v2();

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public accessManagerAddress;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint64 public constant AGENT = 10; // Roles are uint64 (0 is reserved for the ADMIN_ROLE)

    string constant TOKEN_NAME = "BoulderTestToken";
    string constant TOKEN_SYMBOL = "BTT";
    uint8 constant TOKEN_DECIMALS = 6;

    modifier asUnauthorized(address account) {
        vm.prank(account);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, account));
        _;
        vm.stopPrank();
    }

    modifier enginePaused() {
        EngineV1_1(engineProxy).pauseEngine();
        _;
    }

    function _tokenData(
        string memory name,
        string memory symbol,
        address manager
    )
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(engineProxy, manager, initialAdmin, initialAdmin, name, symbol, TOKEN_DECIMALS);
    }

    function _threeAccounts() internal returns (address[] memory) {
        address[] memory accounts = new address[](3);
        accounts[0] = makeAddr("testAddress");
        accounts[1] = makeAddr("testAddress2");
        accounts[2] = makeAddr("testAddress3");
        return accounts;
    }

    function setUp() public {
        engineDeployer = new DeployEngine();

        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin);
        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();
        EngineV1_1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        // Upgrade to v1.1 so all tests run against engine v1.1 (isolated engine tests)
        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        EngineV1_1(engineProxy).upgradeToAndCall(address(newEngineImplementation), "");
        EngineV1_1(engineProxy).unPauseEngine();
        vm.stopPrank();

        // Set token implementation to v1.1 so createToken deploys v1.1 tokens (needed for changeTokenAccessManager)
        tokenV1_1Implementation = new BTtokens_v1();
        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(address(tokenV1_1Implementation));
        EngineV1_1(engineProxy).unPauseEngine();
        vm.stopPrank();
    }

    ////////////////////////////
    /// Initialization Tests ///
    ////////////////////////////

    function testCanNotInitializeWhenInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        EngineV1_1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);
    }

    function testCanNotInitializeWithZeroAddress() public {
        engineDeployer = new DeployEngine();
        // upgrader = new UpgradeBox();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin); //
        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();
        vm.expectRevert(EngineV1_1.BTtokensEngine__AddressCanNotBeZero.selector);
        EngineV1_1(engineProxy).initialize(address(0), tokenImplementationAddress, tokenManagerAddress);

        vm.expectRevert(EngineV1_1.BTtokensEngine__AddressCanNotBeZero.selector);
        EngineV1_1(engineProxy).initialize(address(this), address(0), tokenManagerAddress);

        vm.expectRevert(EngineV1_1.BTtokensEngine__AddressCanNotBeZero.selector);
        EngineV1_1(engineProxy).initialize(address(this), tokenImplementationAddress, address(0));
    }

    function testEngineInitializationState() public {
        EngineV1_1 engine = EngineV1_1(engineProxy);

        bool isInitialized = engine.s_initialized();
        address storedImplementation = engine.s_tokenImplementationAddress();
        address storedAccessManager = engine.s_boulderAccessManagerAddress();
        bool isPaused = engine.s_enginePaused();
        address engineOwner = engine.owner();

        assertEq(isInitialized, true);
        assertEq(isPaused, false);
        assertEq(engineOwner, address(this));
        assertEq(storedImplementation, address(tokenV1_1Implementation));
        assertEq(storedAccessManager, tokenManagerAddress);
    }

    function testInitializeWithValidAddresses() public {
        // Engine is already initialized and upgraded to v1.1 in setUp; assert state
        EngineV1_1 engine = EngineV1_1(engineProxy);
        assertEq(engine.s_initialized(), true);
        assertEq(engine.s_tokenImplementationAddress(), address(tokenV1_1Implementation));
        assertEq(engine.s_boulderAccessManagerAddress(), tokenManagerAddress);
    }

    ///////////////////////////
    /// Deploy Tokens Tests ///
    ///////////////////////////

    function testCreateBTtokenAndSetRoles() public {
        bytes memory data = _tokenData(TOKEN_NAME, TOKEN_SYMBOL, tokenManagerAddress);

        /// @dev address(0) on events means that we dont know the address yet
        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit EngineV1_1.MinterRoleSet(address(0), address(agent));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit EngineV1_1.BurnerRoleSet(address(0), address(agent));

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit EngineV1_1.TokenCreated(address(engineProxy), address(0), TOKEN_NAME, TOKEN_SYMBOL);

        address newToken = EngineV1_1(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);

        assertTrue(newToken != address(0));

        BTtokens_v1 createdToken = BTtokens_v1(newToken);
        assertEq(createdToken.name(), TOKEN_NAME);
        assertEq(createdToken.symbol(), TOKEN_SYMBOL);
        assertEq(createdToken.decimals(), TOKEN_DECIMALS);
    }

    function testShouldFailDeployBTtokenSameNameAndSymbol() public {
        bytes memory data = _tokenData(TOKEN_NAME, TOKEN_SYMBOL, tokenManagerAddress);

        EngineV1_1(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);

        vm.expectRevert(EngineV1_1.BTtokensEngine__TokenNameAndSymbolAlreadyInUsed.selector);
        EngineV1_1(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);
    }

    function testCreateTokenFailsWithoutPermissions() public asUnauthorized(makeAddr("unauthorized")) {
        bytes memory data = _tokenData("UnauthorizedToken", "UTK", tokenManagerAddress);
        address unauthorizedUser = makeAddr("unauthorized");
        EngineV1_1(engineProxy).createToken("UnauthorizedToken", "UTK", data, unauthorizedUser, initialAdmin);
    }

    function testCreateTokenShouldFailIfEnginePaused() public {
        EngineV1_1(engineProxy).pauseEngine();

        bytes memory data = _tokenData("PausedToken", "PTK", tokenManagerAddress);
        vm.expectRevert(EngineV1_1.BTtokensEngine__EnginePaused.selector);
        EngineV1_1(engineProxy).createToken("PausedToken", "PTK", data, agent, initialAdmin);
    }

    function testGrantAndRevokeRoles() public {
        vm.startPrank(initialAdmin);

        BTtokensManager manager = BTtokensManager(tokenManagerAddress);

        /// @dev Grant AGENT role to agent
        manager.grantRole(AGENT, agent, 0);
        (bool isMember,) = manager.hasRole(AGENT, agent);
        assertTrue(isMember);

        /// @dev Revoke AGENT role from agent
        manager.revokeRole(AGENT, agent);
        (bool isMember2,) = manager.hasRole(AGENT, agent);
        assertFalse(isMember2);

        vm.stopPrank();
    }

    //////////////////////////////////////////
    /// Set New Token Implementation Tests ///
    //////////////////////////////////////////

    function testSetNewTokenImplementationAddress() public enginePaused {
        address newImplementation = makeAddr("newImplementation");

        vm.startPrank(address(this));
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        vm.stopPrank();

        EngineV1_1(engineProxy).unPauseEngine();

        assertEq(EngineV1_1(engineProxy).s_tokenImplementationAddress(), newImplementation);
    }

    function testSetNewTokenImplementationAddressShouldFailIfUnauthorized() public asUnauthorized(makeAddr("unauthorized")) {
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(makeAddr("newImplementation"));
    }

    function testSetNewTokenImplementationAddressShouldRevertIfZeroAddress() public enginePaused {
        vm.expectRevert(EngineV1_1.BTtokensEngine__AddressCanNotBeZero.selector);
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(address(0));
    }

    function testSetNewTokenImplementationAddressShouldFailIfAlreadyInUse() public enginePaused {
        address newImplementation = EngineV1_1(engineProxy).s_tokenImplementationAddress();

        vm.expectRevert(EngineV1_1.BTtokensEngine__TokenImplementationAlreadyInUse.selector);
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        EngineV1_1(engineProxy).unPauseEngine();
    }

    function testSetNewTokenImplementationAddressFailsIfNotPaused() public {
        address newImplementation = makeAddr("newImplementation");

        vm.expectRevert(EngineV1_1.BTtokensEngine__EngineNotPaused.selector);
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(newImplementation);
    }

    function testSetNewTokenImplementationAddressEventCheck() public enginePaused {
        address newImplementation = makeAddr("newImplementation");

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit EngineV1_1.NewTokenImplementationSet(address(engineProxy), newImplementation);

        EngineV1_1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        EngineV1_1(engineProxy).unPauseEngine();
    }

    ///////////////////////
    /// Blacklist Tests ///
    ///////////////////////

    modifier deployToken() {
        bytes memory data = _tokenData(TOKEN_NAME, TOKEN_SYMBOL, tokenManagerAddress);
        EngineV1_1(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);
        _;
    }

    function testShouldBlacklistIfCallerIsOwner() public {
        address testAddress = makeAddr("testAddress");
        EngineV1_1(engineProxy).blacklist(testAddress);
        assertTrue(EngineV1_1(engineProxy).isBlacklisted(testAddress));
    }

    function testBlacklistFailsWithoutPermissions() public asUnauthorized(makeAddr("unauthorized")) {
        EngineV1_1(engineProxy).blacklist(makeAddr("testAddress"));
    }

    function testShouldUnblacktistIfCallerIsOwner() public {
        address testAddress = makeAddr("testAddress");
        EngineV1_1(engineProxy).blacklist(testAddress);

        EngineV1_1(engineProxy).unBlacklist(testAddress);
        assertFalse(EngineV1_1(engineProxy).isBlacklisted(testAddress));
    }

    function testBlacklistFailsIfAlreadyBlacklisted() public {
        address testAddress = makeAddr("testAddress");

        EngineV1_1(engineProxy).blacklist(testAddress);

        vm.expectRevert(EngineV1_1.BTtokensEngine__AccountIsBlacklisted.selector);
        EngineV1_1(engineProxy).blacklist(testAddress);
    }

    function testUnBlacklistFailsWithoutPermissions() public {
        address testAddress = makeAddr("testAddress");
        EngineV1_1(engineProxy).blacklist(testAddress);
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("unauthorized"))
        );
        EngineV1_1(engineProxy).unBlacklist(testAddress);
        vm.stopPrank();
    }

    function testUnblacklistFailsIfAlreadyUnblacklisted() public {
        address testAddress = makeAddr("testAddress");

        EngineV1_1(engineProxy).blacklist(testAddress);

        EngineV1_1(engineProxy).unBlacklist(testAddress);

        vm.expectRevert(EngineV1_1.BTtokensEngine__AccountIsNotBlacklisted.selector);
        EngineV1_1(engineProxy).unBlacklist(testAddress);
    }

    function testBlacklistedCanNotTransfer() public deployToken {
        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key));

        /// @dev mint tokens to testAddress
        vm.prank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        /// @dev blacklist testAddress
        EngineV1_1(engineProxy).blacklist(testAddress);

        /// @dev testAddress can not transfer tokens
        vm.prank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transfer(testAddress2, 500);
        vm.stopPrank();
    }

    function testBlacklistedForAllTokens() public deployToken {
        string memory tokenName2 = "BoulderTestToken-2";
        string memory symbol2 = "BTT-2";
        bytes memory data = _tokenData(tokenName2, symbol2, tokenManagerAddress);
        EngineV1_1(engineProxy).createToken(tokenName2, symbol2, data, agent, initialAdmin);

        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");

        bytes32 key1 = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token1 = BTtokens_v1(EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key1));

        bytes32 key2 = keccak256(abi.encodePacked(tokenName2, symbol2));
        BTtokens_v1 token2 = BTtokens_v1(EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key2));

        /// @dev mint tokens1 to testAddress, check: why cannot mint token2 to testAddress in same prank? Using prank it
        /// fails because it changes the address, but using startPrank it works
        vm.startPrank(agent);
        token1.mint(testAddress, 1000);
        token2.mint(testAddress, 1000);
        vm.stopPrank();

        assertEq(token1.balanceOf(testAddress), 1000);
        assertEq(token2.balanceOf(testAddress), 1000);

        EngineV1_1(engineProxy).blacklist(testAddress);

        assertTrue(EngineV1_1(engineProxy).isBlacklisted(testAddress));

        /// @dev testAddress can not transfer tokens
        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token1.transfer(testAddress2, 500);

        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token2.transfer(testAddress2, 500);
        vm.stopPrank();
    }

    function testBatchBlacklist() public deployToken {
        address[] memory accounts = _threeAccounts();
        EngineV1_1(engineProxy).batchBlacklist(accounts);
        assertTrue(EngineV1_1(engineProxy).isBlacklisted(accounts[0]));
        assertTrue(EngineV1_1(engineProxy).isBlacklisted(accounts[1]));
        assertTrue(EngineV1_1(engineProxy).isBlacklisted(accounts[2]));
    }

    function testBatchBlacklistFailsIfUnauthorized() public asUnauthorized(makeAddr("unauthorized")) {
        EngineV1_1(engineProxy).batchBlacklist(_threeAccounts());
    }

    function testBatchUnblacklist() public deployToken {
        address[] memory accounts = _threeAccounts();
        EngineV1_1(engineProxy).batchBlacklist(accounts);
        EngineV1_1(engineProxy).batchUnblacklist(accounts);
        assertFalse(EngineV1_1(engineProxy).isBlacklisted(accounts[0]));
        assertFalse(EngineV1_1(engineProxy).isBlacklisted(accounts[1]));
        assertFalse(EngineV1_1(engineProxy).isBlacklisted(accounts[2]));
    }

    function testBatchUnblacklistFailsIfUnauthorized() public {
        address[] memory accounts = _threeAccounts();
        EngineV1_1(engineProxy).batchBlacklist(accounts);
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("unauthorized"))
        );
        EngineV1_1(engineProxy).batchUnblacklist(accounts);
        vm.stopPrank();
    }

    function testIsBlacklisted() public {
        address testAddress = makeAddr("testAddress");
        assertFalse(EngineV1_1(engineProxy).isBlacklisted(testAddress));
    }

    ///////////////////
    /// Pause Tests ///
    ///////////////////

    function testPauseAndUnpause() public deployToken {
        EngineV1_1(engineProxy).pauseEngine();

        assertTrue(EngineV1_1(engineProxy).isEnginePaused());

        EngineV1_1(engineProxy).unPauseEngine();

        assertFalse(EngineV1_1(engineProxy).isEnginePaused());
    }

    function testTokenCanNotTransferWhenEnginePaused() public deployToken {
        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key));

        /// @dev mint tokens to testAddress
        vm.prank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        /// @dev pause engine
        EngineV1_1(engineProxy).pauseEngine();

        /// @dev testAddress can not transfer tokens
        vm.prank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.transfer(testAddress2, 500);
        vm.stopPrank();
    }

    function testPauseFailsWithoutPermissions() public asUnauthorized(makeAddr("unauthorized")) {
        EngineV1_1(engineProxy).pauseEngine();
    }

    function testUnpauseFailsWithoutPermissions() public enginePaused asUnauthorized(makeAddr("unauthorized")) {
        EngineV1_1(engineProxy).unPauseEngine();
    }

    function testPauseFailsIfAlreadyPaused() public {
        EngineV1_1(engineProxy).pauseEngine();

        assertTrue(EngineV1_1(engineProxy).isEnginePaused());
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        EngineV1_1(engineProxy).pauseEngine();
    }

    function testUnpauseFailsIfNotPaused() public {
        assertFalse(EngineV1_1(engineProxy).isEnginePaused());
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        EngineV1_1(engineProxy).unPauseEngine();
    }

    function testPauseUnpauseEvents() public {
        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit EngineV1_1.EnginePaused(address(engineProxy));

        EngineV1_1(engineProxy).pauseEngine();

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit EngineV1_1.EngineUnpaused(address(engineProxy));

        EngineV1_1(engineProxy).unPauseEngine();
    }

    function testCreateTokenFailsIfPaused() public enginePaused {
        bytes memory data = _tokenData("PausedToken", "PTK", tokenManagerAddress);
        vm.expectRevert(EngineV1_1.BTtokensEngine__EnginePaused.selector);
        EngineV1_1(engineProxy).createToken("PausedToken", "PTK", data, agent, initialAdmin);
    }

    function testUnpauseEngineFailsIfNotPaused() public {
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        EngineV1_1(engineProxy).unPauseEngine();
    }

    /////////////////////
    /// Getters Tests ///
    /////////////////////

    function testGetDeployedTokenProxyAddress() public deployToken {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        address tokenProxyAddress = EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key);

        assertTrue(tokenProxyAddress != address(0));
    }

    function testGetDeployedTokenProxyAddressFailsIfNotDeployed() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        vm.expectRevert(EngineV1_1.BTtokensEngine__TokenNotDeployed.selector);
        EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key);
    }

    function testGetDeployedTokensKeys() public deployToken {
        bytes32[] memory keys = EngineV1_1(engineProxy).getDeployedTokensKeys();

        assertTrue(keys.length == 1);
    }

    function testGetVersion() public {
        string memory version = EngineV1_1(engineProxy).getVersion();
        assertEq(version, "1.1");
    }

    /////////////////////
    /// Manager Tests ///
    /////////////////////

    function testGetAccessManagerForDeployedTokenAfterCreate() public deployToken {
        bytes32 key = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));
        assertEq(EngineV1_1(engineProxy).getAccessManagerForDeployedToken(key), tokenManagerAddress);
    }

    function testGetAccessManagerForDeployedTokenFailsIfNotDeployed() public {
        bytes32 key = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));
        vm.expectRevert(EngineV1_1.BTtokensEngine__TokenNotDeployed.selector);
        EngineV1_1(engineProxy).getAccessManagerForDeployedToken(key);
    }

    function testChangeTokenAccessManager() public deployToken {
        bytes32 key = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));
        address tokenAddress = EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key);

        BTtokensManager secondManager = new BTtokensManager(initialAdmin);
        vm.prank(initialAdmin);
        secondManager.grantRole(ADMIN_ROLE, address(engineProxy), 0);

        vm.prank(address(this));
        EngineV1_1(engineProxy).changeTokenAccessManager(tokenAddress, address(secondManager));

        assertEq(BTtokens_v1(tokenAddress).s_manager(), address(secondManager));
        assertEq(EngineV1_1(engineProxy).getAccessManagerForDeployedToken(key), address(secondManager));
    }

    function testChangeTokenAccessManagerFailsIfUnauthorized() public deployToken {
        bytes32 key = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));
        address tokenAddress = EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key);
        BTtokensManager newManager = new BTtokensManager(initialAdmin);

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        EngineV1_1(engineProxy).changeTokenAccessManager(tokenAddress, address(newManager));
        vm.stopPrank();
    }

    function testChangeTokenAccessManagerFailsIfZeroAddress() public deployToken {
        bytes32 key = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));
        address tokenAddress = EngineV1_1(engineProxy).getDeployedTokenProxyAddress(key);

        vm.expectRevert(EngineV1_1.BTtokensEngine__AddressCanNotBeZero.selector);
        EngineV1_1(engineProxy).changeTokenAccessManager(tokenAddress, address(0));

        vm.expectRevert(EngineV1_1.BTtokensEngine__AddressCanNotBeZero.selector);
        EngineV1_1(engineProxy).changeTokenAccessManager(address(0), tokenManagerAddress);
    }

    function testCreateTokenWithDifferentManagerRecordsManager() public {
        BTtokensManager otherManager = new BTtokensManager(initialAdmin);
        vm.prank(initialAdmin);
        otherManager.grantRole(ADMIN_ROLE, address(engineProxy), 0);

        string memory name2 = "GroupToken";
        string memory symbol2 = "GRP";
        bytes memory data = _tokenData(name2, symbol2, address(otherManager));
        address token2 = EngineV1_1(engineProxy).createToken(name2, symbol2, data, agent, initialAdmin);
        assertTrue(token2 != address(0));

        assertEq(BTtokens_v1(token2).s_manager(), address(otherManager));
        bytes32 salt2 = keccak256(abi.encodePacked(name2, symbol2));
        assertEq(EngineV1_1(engineProxy).getAccessManagerForDeployedToken(salt2), address(otherManager));
    }

    /////////////////////
    /// Upgrade Tests ///
    /////////////////////

    /// @dev Upgrade tests use a fresh v1.0 engine and upgrade to BTtokensEngine_v2 (test double) to verify upgrade works

    function testUpgradeEngine() public {
        (address upgradeProxy,,) = _deployAndInitEngineV1_0();
        vm.startPrank(address(this));
        EngineV1_1(upgradeProxy).pauseEngine();
        EngineV1_1(upgradeProxy).upgradeToAndCall(address(v2EngineImplementation), "");
        EngineV1_1(upgradeProxy).unPauseEngine();
        vm.stopPrank();
        assertEq(BTtokensEngine_v2(upgradeProxy).getVersion(), "2.0");
    }

    function testUpgradeToNewImplementationFailsIfUnauthorized() public {
        (address upgradeProxy,,) = _deployAndInitEngineV1_0();
        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        EngineV1_1(upgradeProxy).upgradeToAndCall(address(v2EngineImplementation), "");
        vm.stopPrank();
    }

    function testEngineUpgradeToNewImplementationFailsIfNotPaused() public {
        (address upgradeProxy,,) = _deployAndInitEngineV1_0();
        vm.startPrank(address(this));
        vm.expectRevert(EngineV1_1.BTtokensEngine__EngineNotPaused.selector);
        EngineV1_1(upgradeProxy).upgradeToAndCall(address(v2EngineImplementation), "");
        vm.stopPrank();
    }

    /// @dev Deploys a fresh engine v1.0 (via DeployEngine), grants role and initializes. For upgrade tests only.
    function _deployAndInitEngineV1_0() internal returns (address proxy, address tokenImpl, address manager) {
        DeployEngine deployer = new DeployEngine();
        (proxy, tokenImpl, manager) = deployer.run(initialAdmin);
        vm.startPrank(initialAdmin);
        BTtokensManager(manager).grantRole(ADMIN_ROLE, proxy, 0);
        vm.stopPrank();
        EngineV1_1(proxy).initialize(address(this), tokenImpl, manager);
    }

    function testNewEngineCanCreateTokens() public {
        bytes memory data = _tokenData(TOKEN_NAME, TOKEN_SYMBOL, tokenManagerAddress);

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit EngineV1_1.MinterRoleSet(address(0), address(agent));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit EngineV1_1.BurnerRoleSet(address(0), address(agent));

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit EngineV1_1.TokenCreated(address(engineProxy), address(0), TOKEN_NAME, TOKEN_SYMBOL);

        address newToken = BTtokensEngine_v2(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);

        assertTrue(newToken != address(0));

        BTtokens_v1 createdToken = BTtokens_v1(newToken);
        assertEq(createdToken.name(), TOKEN_NAME);
        assertEq(createdToken.symbol(), TOKEN_SYMBOL);
        assertEq(createdToken.decimals(), TOKEN_DECIMALS);
    }

    function testDeployShouldFailIfEngineUpgradedAndTokenNameAndSymbolInUse() public deployToken {
        bytes memory data = _tokenData(TOKEN_NAME, TOKEN_SYMBOL, tokenManagerAddress);
        vm.expectRevert(EngineV1_1.BTtokensEngine__TokenNameAndSymbolAlreadyInUsed.selector);
        BTtokensEngine_v2(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);
    }
}
