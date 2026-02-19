// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { DeployEngine } from "./DeployEngine.s.sol";
import { BTtokensEngine_v1 } from "../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokensManager } from "../src/BTContracts/v1.0/BTtokensManager.sol";

/**
 * @title DeployAndInitEngine
 * @notice Deploys engine v1.0 (proxy + impl + manager), grants role to engine, and initializes.
 *        Use this for local testing with Anvil before running UpgradeEngineToV1_1.
 * @dev Run with Anvil default key; then export ENGINE_PROXY from the output and run the upgrade script.
 *
 * Usage (terminal 1):
 *   anvil
 * Usage (terminal 2):
 *   forge script script/DeployAndInitEngine.s.sol:DeployAndInitEngine \
 *     --rpc-url http://localhost:8545 \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast
 *   export ENGINE_PROXY=<printed address>
 *   forge script script/UpgradeEngineToV1_1.s.sol:UpgradeEngineToV1_1 \
 *     --rpc-url http://localhost:8545 \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast
 */
contract DeployAndInitEngine is Script {
    uint64 public constant ADMIN_ROLE = type(uint64).min;

    function run() external {
        address deployer = msg.sender;

        DeployEngine deployerContract = new DeployEngine();
        (address proxy, address tokenImpl, address manager) = deployerContract.run(deployer);

        vm.startBroadcast(deployer);
        BTtokensManager(manager).grantRole(ADMIN_ROLE, proxy, 0);
        BTtokensEngine_v1(proxy).initialize(deployer, tokenImpl, manager);
        vm.stopBroadcast();

        console2.log("\n=== Engine v1.0 deployed and initialized ===");
        console2.log("Engine Proxy (use for upgrade):", proxy);
        console2.log("Token Implementation:", tokenImpl);
        console2.log("Manager:", manager);
        console2.log("\nExport and run upgrade:");
        console2.log("  export ENGINE_PROXY=", proxy);
        console2.log("  forge script script/UpgradeEngineToV1_1.s.sol:UpgradeEngineToV1_1 \\");
        console2.log("    --rpc-url http://localhost:8545 \\");
        console2.log("    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \\");
        console2.log("    --broadcast");
    }
}
