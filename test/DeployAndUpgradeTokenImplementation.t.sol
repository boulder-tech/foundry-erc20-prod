// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test, console, console2 } from "forge-std/Test.sol";
import { DeployEngine } from "../script/DeployEngine.s.sol";
// import {UpgradeBox} from "../script/UpgradeBox.s.sol";
import { BTtokensEngine } from "../src/BTtokensEngine.sol";
import { BTtokens } from "../src/BTtokens.sol";
// import {BoxV2} from "../src/BoxV2.sol";

contract DeployAndUpgradeTest is Test {
    DeployEngine public engineDeployer;
    // UpgradeBox public upgrader;
    address public engineProxy;
    address public tokenImplementationAddress;

    function setUp() public {
        engineDeployer = new DeployEngine();
        // upgrader = new UpgradeBox();
        (engineProxy, tokenImplementationAddress) = engineDeployer.run(); //
    }

    function testDeployedBTtokensEngine() public {
        BTtokensEngine(engineProxy).initialize(address(this), tokenImplementationAddress);
        bool isInitialized = BTtokensEngine(engineProxy).s_initialized();
        assertEq(isInitialized, true);
    }

    // function testDeployBTtoken() public {
    //     string memory tokenName = "BoulderTestToken";
    //     string memory tokenSymbol = "BTT";
    //     address tokenManager = address(0);
    //     address tokenOwner = engineProxy;
    //     uint8 tokenDecimals = 6;

    //     bytes memory data = abi.encode(engineProxy, tokenManager, tokenOwner, tokenName, tokenSymbol, tokenDecimals);

    //     address newProxyToken = BTtokensEngine(engineProxy).createToken(tokenName, tokenSymbol, data);

    //     vm.expectEmit(address(engineProxy));
    //     emit TokenCreated(address(newProxyToken), tokenName, tokenSymbol);
    // }
}
