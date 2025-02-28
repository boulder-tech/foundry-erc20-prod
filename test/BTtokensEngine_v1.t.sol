// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test, console, console2 } from "forge-std/Test.sol";
import { DeployEngine } from "../script/DeployEngine.s.sol";
import { BTtokensEngine_v1, OwnableUpgradeable, Initializable } from "../src/BTtokensEngine_v1.sol";
import { BTtokens_v1 } from "../src/BTtokens_v1.sol";
import { BTtokensManager } from "../src/BTtokensManager.sol";

contract DeployAndUpgradeTest is Test {
    DeployEngine public engineDeployer;
    // UpgradeBox public upgrader;
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
        // upgrader = new UpgradeBox();
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
        address storedAccessManager = engine.s_accessManagerAddress();
        bool enginePaused = engine.s_enginePaused();
        address engineOwner = engine.owner();

        assertEq(isInitialized, true);
        assertEq(enginePaused, false);
        assertEq(engineOwner, address(this));
        assertEq(storedImplementation, tokenImplementationAddress);
        assertEq(storedAccessManager, tokenManagerAddress);
    }

    ///////////////////////////
    /// Deploy Tokens Tests ///
    ///////////////////////////

    function testDeployBTtokenAndSetRoles() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = address(0);
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.MinterRoleSet(address(0), address(agent));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.BurnerRoleSet(address(0), address(agent));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.PauserRoleSet(address(0), address(engineProxy));

        vm.expectEmit(false, true, true, true, address(engineProxy));
        emit BTtokensEngine_v1.UnPauserRoleSet(address(0), address(engineProxy));

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit BTtokensEngine_v1.TokenCreated(address(engineProxy), address(0), tokenName, tokenSymbol);

        address newToken = BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);

        assertTrue(newToken != address(0));

        BTtokens_v1 createdToken = BTtokens_v1(newToken);
        assertEq(createdToken.name(), tokenName);
        assertEq(createdToken.symbol(), tokenSymbol);
        assertEq(createdToken.decimals(), tokenDecimals);
    }

    function testShouldFailDeployBTtokenSameNameAndSymbol() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = address(0);
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);

        vm.expectRevert(BTtokensEngine_v1.BTtokensEngine__TokenNameAndSymbolAlreadyInUsed.selector);
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCreateTokenFailsWithoutPermissions() public {
        string memory tokenName = "UnauthorizedToken";
        string memory tokenSymbol = "UTK";
        bytes memory data = abi.encode(engineProxy, tokenManagerAddress, initialAdmin, tokenName, tokenSymbol, 6);

        address unauthorizedUser = makeAddr("unauthorized");

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorizedUser)
        );
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, unauthorizedUser);
        vm.stopPrank();
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

    function testUpgradeTokenImplementationAddress() public {
        address newImplementation = makeAddr("newImplementation");

        vm.startPrank(address(this));
        BTtokensEngine_v1(engineProxy).setNewTokenImplementationAddress(newImplementation);
        vm.stopPrank();

        assertEq(BTtokensEngine_v1(engineProxy).s_tokenImplementationAddress(), newImplementation);
    }
}
