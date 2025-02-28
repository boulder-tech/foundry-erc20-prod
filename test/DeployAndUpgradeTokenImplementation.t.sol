// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test, console, console2 } from "forge-std/Test.sol";
import { DeployEngine } from "../script/DeployEngine.s.sol";
// import {UpgradeBox} from "../script/UpgradeBox.s.sol";
import { BTtokensEngine_v1 } from "../src/BTtokensEngine_v1.sol";
import { BTtokens_v1 } from "../src/BTtokens_v1.sol";
import { BTtokensManager } from "../src/BTtokensManager.sol";
// import {BoxV2} from "../src/BoxV2.sol";

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

    function testDeployedBTtokensEngineInitialization() public {
        bool isInitialized = BTtokensEngine_v1(engineProxy).s_initialized();
        assertEq(isInitialized, true);
    }

    function testDeployBTtokenAndSetRoles() public {
        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        address tokenManager = address(0);
        address tokenOwner = initialAdmin;
        uint8 tokenDecimals = 6;

        bytes memory data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

        vm.expectEmit(true, false, true, true, address(engineProxy));
        emit BTtokensEngine_v1.TokenCreated(address(engineProxy), address(0), tokenName, tokenSymbol);

        BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent);
    }
    // emit TargetFunctionRoleUpdated(target, selector, roleId);
}
