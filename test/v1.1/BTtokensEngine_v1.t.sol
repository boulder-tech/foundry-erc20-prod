// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test, console, console2 } from "forge-std/Test.sol";
import { DeployEngine } from "../../script/DeployEngine.s.sol";
import {
    BTtokensEngine_v1,
    OwnableUpgradeable,
    Initializable,
    BTtokenProxy,
    PausableUpgradeable
} from "../../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { BTtokens_v1, AccessManagedUpgradeable } from "../../src/BTContracts/v1.1/BTtokens_v1.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { BTtokensManager } from "../../src/BTContracts/v1.1/BTtokensManager.sol";

contract BTtokensEngine_v2 is BTtokensEngine_v1 {
    /**
     * @dev Function that returns the version of the contract.
     * @return string memory The version of the contract.
     */
    function getVersion() external pure virtual override returns (string memory) {
        return "1.1";
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

    BTtokensEngine_v2 newEngineImplementation = new BTtokensEngine_v2();

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public accessManagerAddress;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint64 public constant AGENT = 10; // Roles are uint64 (0 is reserved for the ADMIN_ROLE)

    function setUp() public {
        engineDeployer = new DeployEngine();

        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin); //
        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();
        BTtokensEngine_v1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);
    }

    ////////////////////////////
    /// Initialization Tests ///
    ////////////////////////////

    function testCanNotInitializeWhenInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        BTtokensEngine_v1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);
    }

    function testCanNotInitializeWithZeroAddress() public {
        engineDeployer = new DeployEngine();
        // upgrader = new UpgradeBox();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin); //
        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();
        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__AddressCanNotBeZero.selector);
        BTtokensEngine_v1(engineProxy).initialize(address(0), tokenImplementationAddress, tokenManagerAddress);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__AddressCanNotBeZero.selector);
        BTtokensEngine_v1(engineProxy).initialize(address(this), address(0), tokenManagerAddress);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__AddressCanNotBeZero.selector);
        BTtokensEngine_v1(engineProxy).initialize(address(this), tokenImplementationAddress, address(0));
    }

    function testEngineInitializationState() public {
        BTtokensEngine_v1 engine = BTtokensEngine_v1(engineProxy);

        bool isInitialized = engine.s_initialized();
        address storedImplementation = engine.s_tokenImplementationAddress();
        address storedAccessManager = engine.s_boulderAccessManagerAddress();
        bool enginePaused = engine.s_enginePaused();
        address engineOwner = engine.owner();

        assertEq(isInitialized, true);
        assertEq(enginePaused, false);
        assertEq(engineOwner, address(this));
        assertEq(storedImplementation, tokenImplementationAddress);
        assertEq(storedAccessManager, tokenManagerAddress);
    }

    function testInitializeWithValidAddresses() public {
        engineDeployer = new DeployEngine();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin);
        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();
        BTtokensEngine_v1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        BTtokensEngine_v1 engine = BTtokensEngine_v1(engineProxy);
        assertEq(engine.s_initialized(), true);
        assertEq(engine.s_tokenImplementationAddress(), tokenImplementationAddress);
        assertEq(engine.s_boulderAccessManagerAddress(), tokenManagerAddress);
    }

    ///////////////////////////
    /// Deploy Tokens Tests ///
    ///////////////////////////

    function testCreateBTtokenAndSetRoles() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        address tokenHolder = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data =
            abi.encode(engineProxy, tokenManager, tokenOwner, tokenHolder, tokenName, tokenSymbol, tokenDecimals);

        /// @dev address(0) on events means that we dont know the address yet
        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.MinterRoleSet(address(0), address(agent));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.BurnerRoleSet(address(0), address(agent));

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit BTtokensEngine_v1.TokenCreated(address(engineProxy), address(0), tokenName, tokenSymbol);

        address newToken = BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);

        assertTrue(newToken != address(0));

        BTtokens_v1 createdToken = BTtokens_v1(newToken);
        assertEq(createdToken.name(), tokenName);
        assertEq(createdToken.symbol(), tokenSymbol);
        assertEq(createdToken.decimals(), tokenDecimals);
    }

    function testShouldFailDeployBTtokenSameNameAndSymbol() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        address tokenHolder = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data =
            abi.encode(engineProxy, tokenManager, tokenOwner, tokenHolder, tokenName, tokenSymbol, tokenDecimals);

        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__TokenNameAndSymbolAlreadyInUsed.selector);
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);
    }

    function testCreateTokenFailsWithoutPermissions() public {
        string memory tokenName = "UnauthorizedToken";
        string memory tokenSymbol = "UTK";
        address tokenOwner = initialAdmin;
        bytes memory data =
            abi.encode(engineProxy, tokenManagerAddress, initialAdmin, initialAdmin, tokenName, tokenSymbol, 6);

        address unauthorizedUser = makeAddr("unauthorized");

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, unauthorizedUser, tokenOwner);
        vm.stopPrank();
    }

    function testCreateTokenShouldFailIfEnginePaused() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        string memory tokenName = "PausedToken";
        string memory tokenSymbol = "PTK";
        address tokenOwner = initialAdmin;
        bytes memory data =
            abi.encode(engineProxy, tokenManagerAddress, initialAdmin, initialAdmin, tokenName, tokenSymbol, 6);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__EnginePaused.selector);
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);
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

    function testSetNewTokenImplementationAddress() public {
        address newImplementation = makeAddr("newImplementation");

        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(address(this));
        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).unPauseEngine();

        assertEq(BTtokensEngine_v1(engineProxy).s_tokenImplementationAddress(), newImplementation);
    }

    function testSetNewTokenImplementationAddressShouldFailIfUnauthorized() public {
        address newImplementation = makeAddr("newImplementation");

        address unauthorized = makeAddr("unauthorized");

        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        vm.stopPrank();
    }

    function testSetNewTokenImplementationAddressShouldRevertIfZeroAddress() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();
        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__AddressCanNotBeZero.selector);
        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(address(0));
    }

    function testSetNewTokenImplementationAddressShouldFailIfAlreadyInUse() public {
        address newImplementation = BTtokensEngine_v1(engineProxy).s_tokenImplementationAddress();

        BTtokensEngine_v1(engineProxy).pauseEngine();
        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__TokenImplementationAlreadyInUse.selector);
        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        BTtokensEngine_v1(engineProxy).unPauseEngine();
    }

    function testSetNewTokenImplementationAddressFailsIfNotPaused() public {
        address newImplementation = makeAddr("newImplementation");

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__EngineNotPaused.selector);
        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(newImplementation);
    }

    function testSetNewTokenImplementationAddressEventCheck() public {
        address newImplementation = makeAddr("newImplementation");

        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit BTtokensEngine_v1.NewTokenImplementationSet(address(engineProxy), newImplementation);

        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        BTtokensEngine_v1(engineProxy).unPauseEngine();
    }

    ///////////////////////
    /// Blacklist Tests ///
    ///////////////////////

    modifier deployToken() {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        address tokenHolder = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data =
            abi.encode(engineProxy, tokenManager, tokenOwner, tokenHolder, tokenName, tokenSymbol, tokenDecimals);

        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);

        _;
    }

    function testShouldBlacklistIfCallerIsOwner() public {
        address testAddress = makeAddr("testAddress");
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);
        assertTrue(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress));
    }

    function testBlacklistFailsWithoutPermissions() public {
        address testAddress = makeAddr("testAddress");

        address unauthorizedUser = makeAddr("unauthorized");

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);
        vm.stopPrank();
    }

    function testShouldUnblacktistIfCallerIsOwner() public {
        address testAddress = makeAddr("testAddress");
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        BTtokensEngine_v1(engineProxy).unBlacklist(testAddress);
        assertFalse(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress));
    }

    function testBlacklistFailsIfAlreadyBlacklisted() public {
        address testAddress = makeAddr("testAddress");

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__AccountIsBlacklisted.selector);
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);
    }

    function testUnBlacklistFailsWithoutPermissions() public {
        address testAddress = makeAddr("testAddress");
        address unauthorizedUser = makeAddr("unauthorized");

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).unBlacklist(testAddress);
        vm.stopPrank();
    }

    function testUnblacklistFailsIfAlreadyUnblacklisted() public {
        address testAddress = makeAddr("testAddress");

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        BTtokensEngine_v1(engineProxy).unBlacklist(testAddress);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__AccountIsNotBlacklisted.selector);
        BTtokensEngine_v1(engineProxy).unBlacklist(testAddress);
    }

    function testBlacklistedCanNotTransfer() public deployToken {
        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        /// @dev mint tokens to testAddress
        vm.prank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        /// @dev blacklist testAddress
        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        /// @dev testAddress can not transfer tokens
        vm.prank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.transfer(testAddress2, 500);
        vm.stopPrank();
    }

    function testBlacklistedForAllTokens() public deployToken {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        address tokenHolder = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data =
            abi.encode(engineProxy, tokenManager, tokenOwner, tokenHolder, tokenName, tokenSymbol, tokenDecimals);

        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);

        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");

        bytes32 key1 = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token1 = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key1));

        bytes32 key2 = keccak256(abi.encodePacked("BoulderTestToken-2", "BTT-2"));
        BTtokens_v1 token2 = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key2));

        /// @dev mint tokens1 to testAddress, check: why cannot mint token2 to testAddress in same prank? Using prank it
        /// fails because it changes the address, but using startPrank it works
        vm.startPrank(agent);
        token1.mint(testAddress, 1000);
        token2.mint(testAddress, 1000);
        vm.stopPrank();

        assertEq(token1.balanceOf(testAddress), 1000);
        assertEq(token2.balanceOf(testAddress), 1000);

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        assertTrue(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress));

        /// @dev testAddress can not transfer tokens
        vm.startPrank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token1.transfer(testAddress2, 500);

        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token2.transfer(testAddress2, 500);
        vm.stopPrank();
    }

    function testBatchBlacklist() public deployToken {
        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        address testAddress3 = makeAddr("testAddress3");

        address[] memory accounts = new address[](3);
        accounts[0] = testAddress;
        accounts[1] = testAddress2;
        accounts[2] = testAddress3;

        BTtokensEngine_v1(engineProxy).batchBlacklist(accounts);

        assertTrue(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress));
        assertTrue(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress2));
        assertTrue(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress3));
    }

    function testBatchBlacklistFailsIfUnauthorized() public {
        address unauthorizedUser = makeAddr("unauthorized");

        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        address testAddress3 = makeAddr("testAddress3");

        address[] memory accounts = new address[](3);
        accounts[0] = testAddress;
        accounts[1] = testAddress2;
        accounts[2] = testAddress3;

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).batchBlacklist(accounts);
        vm.stopPrank();
    }

    function testBatchUnblacklist() public deployToken {
        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        address testAddress3 = makeAddr("testAddress3");

        address[] memory accounts = new address[](3);
        accounts[0] = testAddress;
        accounts[1] = testAddress2;
        accounts[2] = testAddress3;

        BTtokensEngine_v1(engineProxy).batchBlacklist(accounts);

        BTtokensEngine_v1(engineProxy).batchUnblacklist(accounts);

        assertFalse(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress));
        assertFalse(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress2));
        assertFalse(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress3));
    }

    function testBatchUnblacklistFailsIfUnauthorized() public {
        address unauthorizedUser = makeAddr("unauthorized");

        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        address testAddress3 = makeAddr("testAddress3");

        address[] memory accounts = new address[](3);
        accounts[0] = testAddress;
        accounts[1] = testAddress2;
        accounts[2] = testAddress3;

        BTtokensEngine_v1(engineProxy).batchBlacklist(accounts);

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).batchUnblacklist(accounts);
        vm.stopPrank();
    }

    function testIsBlacklisted() public {
        address testAddress = makeAddr("testAddress");
        assertFalse(BTtokensEngine_v1(engineProxy).isBlacklisted(testAddress));
    }

    ///////////////////
    /// Pause Tests ///
    ///////////////////

    function testPauseAndUnpause() public deployToken {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        assertTrue(BTtokensEngine_v1(engineProxy).isEnginePaused());

        BTtokensEngine_v1(engineProxy).unPauseEngine();

        assertFalse(BTtokensEngine_v1(engineProxy).isEnginePaused());
    }

    function testTokenCanNotTransferWhenEnginePaused() public deployToken {
        address testAddress = makeAddr("testAddress");
        address testAddress2 = makeAddr("testAddress2");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        /// @dev mint tokens to testAddress
        vm.prank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        /// @dev pause engine
        BTtokensEngine_v1(engineProxy).pauseEngine();

        /// @dev testAddress can not transfer tokens
        vm.prank(testAddress);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.transfer(testAddress2, 500);
        vm.stopPrank();
    }

    function testPauseFailsWithoutPermissions() public {
        address unauthorizedUser = makeAddr("unauthorized");

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).pauseEngine();
        vm.stopPrank();
    }

    function testUnpauseFailsWithoutPermissions() public {
        address unauthorizedUser = makeAddr("unauthorized");

        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).unPauseEngine();
        vm.stopPrank();
    }

    function testPauseFailsIfAlreadyPaused() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        assertTrue(BTtokensEngine_v1(engineProxy).isEnginePaused());
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        BTtokensEngine_v1(engineProxy).pauseEngine();
    }

    function testUnpauseFailsIfNotPaused() public {
        assertFalse(BTtokensEngine_v1(engineProxy).isEnginePaused());
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        BTtokensEngine_v1(engineProxy).unPauseEngine();
    }

    function testPauseUnpauseEvents() public {
        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit BTtokensEngine_v1.EnginePaused(address(engineProxy));

        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.EngineUnpaused(address(engineProxy));

        BTtokensEngine_v1(engineProxy).unPauseEngine();
    }

    function testCreateTokenFailsIfPaused() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        string memory tokenName = "PausedToken";
        string memory tokenSymbol = "PTK";
        address tokenOwner = initialAdmin;
        bytes memory data = abi.encode(engineProxy, tokenManagerAddress, initialAdmin, tokenName, tokenSymbol, 6);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__EnginePaused.selector);
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);
    }

    function testUnpauseEngineFailsIfNotPaused() public {
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        BTtokensEngine_v1(engineProxy).unPauseEngine();
    }

    /////////////////////
    /// Getters Tests ///
    /////////////////////

    function testGetDeployedTokenProxyAddress() public deployToken {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        address tokenProxyAddress = BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key);

        assertTrue(tokenProxyAddress != address(0));
    }

    function testGetDeployedTokenProxyAddressFailsIfNotDeployed() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__TokenNotDeployed.selector);
        BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key);
    }

    function testGetDeployedTokensKeys() public deployToken {
        bytes32[] memory keys = BTtokensEngine_v1(engineProxy).getDeployedTokensKeys();

        assertTrue(keys.length == 1);
    }

    function testGetVersion() public {
        string memory version = BTtokensEngine_v1(engineProxy).getVersion();
        assertEq(version, "1.1");
    }

    /////////////////////
    /// Upgrade Tests ///
    /////////////////////

    /// @dev new implementation should reinitialize the contract? Not necessary

    function testUpgradeEngine() public {
        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(address(this));

        BTtokensEngine_v1(engineProxy).upgradeToAndCall(address(newEngineImplementation), "");

        vm.stopPrank();

        assertEq(BTtokensEngine_v2(engineProxy).getVersion(), "1.1");
    }

    function testUpgradeToNewImplementationFailsIfUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");

        vm.startPrank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        BTtokensEngine_v1(engineProxy).upgradeToAndCall(address(newEngineImplementation), "");
        vm.stopPrank();
    }

    function testEngineUpgradeToNewImplementationFailsIfNotPaused() public {
        vm.startPrank(address(this));
        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__EngineNotPaused.selector);
        BTtokensEngine_v1(engineProxy).upgradeToAndCall(address(newEngineImplementation), "");
        vm.stopPrank();
    }

    modifier engineUpgraded() {
        vm.startPrank(address(this));

        BTtokensEngine_v1(engineProxy).pauseEngine();
        BTtokensEngine_v1(engineProxy).upgradeToAndCall(address(newEngineImplementation), "");
        BTtokensEngine_v1(engineProxy).unPauseEngine();
        vm.stopPrank();

        _;
    }

    function testNewEngineCanCreateTokens() public engineUpgraded {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        address tokenHolder = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data =
            abi.encode(engineProxy, tokenManager, tokenOwner, tokenHolder, tokenName, tokenSymbol, tokenDecimals);

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.MinterRoleSet(address(0), address(agent));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.BurnerRoleSet(address(0), address(agent));

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit BTtokensEngine_v1.TokenCreated(address(engineProxy), address(0), tokenName, tokenSymbol);

        address newToken = BTtokensEngine_v2(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);

        assertTrue(newToken != address(0));

        BTtokens_v1 createdToken = BTtokens_v1(newToken);
        assertEq(createdToken.name(), tokenName);
        assertEq(createdToken.symbol(), tokenSymbol);
        assertEq(createdToken.decimals(), tokenDecimals);
    }

    function testDeployShouldFailIfEngineUpgradedAndTokenNameAndSymbolInUse() public deployToken engineUpgraded {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__TokenNameAndSymbolAlreadyInUsed.selector);
        BTtokensEngine_v2(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);
    }
}
