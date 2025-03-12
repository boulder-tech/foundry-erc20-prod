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
import { BTtokens_v1, AccessManagedUpgradeable } from "../src/BTtokens_v1.sol";
import { IAccessManaged } from "@openzeppelin/contracts/access/manager/IAccessManaged.sol";
import { BTtokensManager } from "../src/BTtokensManager.sol";

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

    BTtokens_v2 newTokenImplementation = new BTtokens_v2();

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public accessManagerAddress;
    address public tokenAddress;
    bytes data;

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

        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        tokenAddress = BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
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
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("invalid argument - empty string");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWithEmptySymbol() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("invalid argument - empty string");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWithInvalidDecimals() public {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 19;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("decimals between 0 and 18");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWhenEngineIsZeroAddress() public {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        data = abi.encode(address(0), tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("engine can not be address 0");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    function testCanNotInitializeWhenTokenManagerIsZeroAddress() public {
        string memory tokenName = "BoulderTestToken-2";
        string memory tokenSymbol = "BTT-2";
        address tokenManager = address(0);
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectRevert("token manager can not be address 0");
        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    ///////////////////////
    /// Variables Tests ///
    ///////////////////////

    function testTokenName() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.name(), "BoulderTestToken");
    }

    function testTokenSymbol() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.symbol(), "BTT");
    }

    function testTokenDecimals() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.decimals(), 6);
    }

    function testTokenTotalSupply() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.totalSupply(), 0);
    }

    function testTokenManager() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.manager(), tokenManagerAddress);
    }

    function testTokenEngine() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.engine(), engineProxy);
    }

    function testTokenOwner() public {
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        assertEq(token.owner(), initialAdmin);
    }

    ////////////////////
    /// Supply Tests ///
    ////////////////////

    function testAgentCanMint() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        vm.startPrank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        assertEq(token.totalSupply(), 1000);
    }

    function testUnauthorizedCanNotMint() public {
        address testAddress = makeAddr("unauthorized");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        vm.prank(testAddress);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, testAddress));
        token.mint(testAddress, 1000);
        vm.stopPrank();
    }

    function testAgentCanNotMintIfEnginePaused() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        BTtokensEngine_v1(engineProxy).pauseEngine();

        vm.startPrank(agent);
        vm.expectRevert(BTtokens_v1.BTtokens__EngineIsPaused.selector);
        token.mint(testAddress, 1000);
        vm.stopPrank();
    }

    function testAgentCanNotMintIfAccountBlacklisted() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(agent);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsBlacklisted.selector);
        token.mint(testAddress, 1000);
        vm.stopPrank();
    }

    function testAgentCanBurnIfBlacklisted() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        vm.startPrank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).blacklist(testAddress);

        vm.startPrank(agent);
        token.burn(testAddress, 500);
        vm.stopPrank();

        assertEq(token.totalSupply(), 500);
    }

    function testAgentCanNotBurnIfNotBlacklisted() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        vm.startPrank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        vm.startPrank(agent);
        vm.expectRevert(BTtokens_v1.BTtokens__AccountIsNotBlacklisted.selector);
        token.burn(testAddress, 500);
        vm.stopPrank();

        assertEq(token.totalSupply(), 1000);
    }

    /// @dev When doing this test _update has the modifier whenNotEnginePaused, so it reverts. Removed that modifier
    /// from the _update function to pass this test.
    function testAgentCanBurnIfBlacklistedAndEnginePaused() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

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
}
