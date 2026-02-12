// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { BTtokensEngine_v1 as EngineV1_0 } from "../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokensEngine_v1 as EngineV1_1 } from "../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UpgradeEngineToV1_1
 * @notice Script to upgrade the engine proxy from v1.0 to v1.1 on Base Sepolia.
 * @dev IMPORTANT: This script assumes:
 *      1. The engine proxy is already deployed and initialized (v1.0)
 *      2. You are the owner of the engine proxy
 *      3. The engine is NOT paused (will pause it before upgrade)
 *      4. After upgrade, you must also upgrade tokens individually (see UpgradeTokenToV1_1.s.sol)
 * 
 * Usage:
 *   forge script script/UpgradeEngineToV1_1.s.sol:UpgradeEngineToV1_1 \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $BASESCAN_API_KEY \
 *     -vvvv
 */
contract UpgradeEngineToV1_1 is Script {
    // Set these via environment variables or modify directly
    address public constant ENGINE_PROXY = address(0); // TODO: Set your engine proxy address
    address public owner; // Will be set from msg.sender or env var

    function setUp() public {
        // Try to get owner from env, otherwise use msg.sender
        try vm.envAddress("ENGINE_OWNER") returns (address envOwner) {
            owner = envOwner;
        } catch {
            owner = msg.sender;
        }
    }

    function run() external {
        require(ENGINE_PROXY != address(0), "ENGINE_PROXY must be set");
        
        console2.log("=== Engine Upgrade to v1.1 ===");
        console2.log("Engine Proxy:", ENGINE_PROXY);
        console2.log("Owner:", owner);
        console2.log("Current version:", EngineV1_0(ENGINE_PROXY).getVersion());

        vm.startBroadcast(owner);

        // 1. Deploy new v1.1 implementation
        // NOTE: This implementation will be automatically verified on BaseScan
        // when using --verify flag. Check BaseScan after deployment to confirm.
        console2.log("\n1. Deploying engine v1.1 implementation...");
        EngineV1_1 engineV1_1Implementation = new EngineV1_1();
        console2.log("Engine v1.1 Implementation:", address(engineV1_1Implementation));
        console2.log("NOTE: Verify this contract on BaseScan after deployment");

        // 2. Verify current state
        EngineV1_0 engine = EngineV1_0(ENGINE_PROXY);
        require(engine.owner() == owner, "Caller is not the owner");
        require(!engine.isEnginePaused(), "Engine is already paused");
        console2.log("\n2. Current state verified");

        // 3. Pause engine (required for upgrade)
        console2.log("\n3. Pausing engine...");
        engine.pauseEngine();
        require(engine.isEnginePaused(), "Engine pause failed");
        console2.log("Engine paused successfully");

        // 4. Perform upgrade
        console2.log("\n4. Upgrading engine to v1.1...");
        engine.upgradeToAndCall(address(engineV1_1Implementation), "");
        console2.log("Upgrade transaction sent");

        // 5. Verify upgrade
        EngineV1_1 engineV1_1 = EngineV1_1(ENGINE_PROXY);
        require(keccak256(bytes(engineV1_1.getVersion())) == keccak256(bytes("1.1")), "Version mismatch");
        console2.log("Version after upgrade:", engineV1_1.getVersion());

        // 6. Unpause engine
        console2.log("\n5. Unpausing engine...");
        engineV1_1.unPauseEngine();
        require(!engineV1_1.isEnginePaused(), "Engine unpause failed");
        console2.log("Engine unpaused successfully");

        vm.stopBroadcast();

        console2.log("\n=== Upgrade Complete ===");
        console2.log("\nVerification:");
        console2.log("The new implementation contract should be verified on BaseScan.");
        console2.log("If verification failed, manually verify at:");
        console2.log("  https://sepolia.basescan.org/address/", address(engineV1_1Implementation));
        console2.log("\nNext steps:");
        console2.log("1. Deploy token v1.1 implementation");
        console2.log("2. Call setNewTokenImplementationAddress(tokenV1_1Implementation)");
        console2.log("3. Upgrade existing tokens using UpgradeTokenToV1_1.s.sol");
    }
}
