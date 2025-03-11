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

contract BTtokensEngine_v2 is BTtokensEngine_v1 {
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
    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner { }
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

        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = tokenManagerAddress;
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }

    //////////////////////
    /// BTtokens Tests ///
    //////////////////////

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

    function testTokenBalanceOf() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        vm.startPrank(agent);
        token.mint(testAddress, 1000);
        vm.stopPrank();

        vm.startPrank(testAddress);
        assertEq(token.balanceOf(testAddress), 1000);
        vm.stopPrank();
    }

    function testOnlyAgentCanMint() public {
        address testAddress = makeAddr("testAddress");
        bytes32 key = keccak256(abi.encodePacked("BoulderTestToken", "BTT"));
        BTtokens_v1 token = BTtokens_v1(BTtokensEngine_v1(engineProxy).getDeployedTokenProxyAddress(key));

        vm.prank(testAddress);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, testAddress));
        token.mint(testAddress, 1000);
        vm.stopPrank();
    }
}
