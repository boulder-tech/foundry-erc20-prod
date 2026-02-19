// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { BTtokens_v1 as TokenV1_0 } from "../src/BTContracts/v1.0/BTtokens_v1.sol";
import { BTtokens_v1 as TokenV1_1 } from "../src/BTContracts/v1.1/BTtokens_v1.sol";
import { BTtokensEngine_v1 } from "../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UpgradeTokenToV1_1
 * @notice Script to upgrade a token proxy from v1.0 to v1.1 on Base Sepolia.
 * @dev IMPORTANT: This script assumes:
 *      1. The engine has already been upgraded to v1.1
 *      2. The token v1.1 implementation has been deployed and set in the engine
 *      3. You are the owner of the token proxy
 *      4. The engine is paused (will pause if not)
 * 
 * Usage:
 *   forge script script/UpgradeTokenToV1_1.s.sol:UpgradeTokenToV1_1 \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $BASESCAN_API_KEY \
 *     -vvvv
 */
contract UpgradeTokenToV1_1 is Script {
    // Set these via environment variables or modify directly
    address public constant TOKEN_PROXY = address(0); // TODO: Set your token proxy address
    address public constant ENGINE_PROXY = address(0); // TODO: Set your engine proxy address
    address public tokenOwner; // Will be set from msg.sender or env var

    function setUp() public {
        // Try to get owner from env, otherwise use msg.sender
        try vm.envAddress("TOKEN_OWNER") returns (address envOwner) {
            tokenOwner = envOwner;
        } catch {
            tokenOwner = msg.sender;
        }
    }

    function run() external {
        require(TOKEN_PROXY != address(0), "TOKEN_PROXY must be set");
        require(ENGINE_PROXY != address(0), "ENGINE_PROXY must be set");
        
        console2.log("=== Token Upgrade to v1.1 ===");
        console2.log("Token Proxy:", TOKEN_PROXY);
        console2.log("Engine Proxy:", ENGINE_PROXY);
        console2.log("Token Owner:", tokenOwner);
        console2.log("Current version:", TokenV1_0(TOKEN_PROXY).getVersion());

        vm.startBroadcast(tokenOwner);

        // 1. Verify engine is v1.1
        BTtokensEngine_v1 engine = BTtokensEngine_v1(ENGINE_PROXY);
        require(keccak256(bytes(engine.getVersion())) == keccak256(bytes("1.1")), "Engine must be v1.1");
        console2.log("\n1. Engine version verified:", engine.getVersion());

        // 2. Get token v1.1 implementation from engine
        address tokenV1_1Implementation = engine.s_tokenImplementationAddress();
        require(tokenV1_1Implementation != address(0), "Token v1.1 implementation not set in engine");
        console2.log("Token v1.1 Implementation:", tokenV1_1Implementation);

        // 3. Verify token owner
        TokenV1_0 token = TokenV1_0(TOKEN_PROXY);
        require(token.owner() == tokenOwner, "Caller is not the token owner");
        console2.log("\n2. Token ownership verified");

        // 4. Ensure engine is paused (required for token upgrade)
        if (!engine.isEnginePaused()) {
            console2.log("\n3. Pausing engine (required for token upgrade)...");
            vm.stopBroadcast();
            vm.startBroadcast(engine.owner());
            engine.pauseEngine();
            vm.stopBroadcast();
            vm.startBroadcast(tokenOwner);
        } else {
            console2.log("\n3. Engine is already paused");
        }

        // 5. Perform token upgrade
        console2.log("\n4. Upgrading token to v1.1...");
        token.upgradeToAndCall(tokenV1_1Implementation, "");
        console2.log("Upgrade transaction sent");

        // 6. Verify upgrade
        TokenV1_1 tokenV1_1 = TokenV1_1(TOKEN_PROXY);
        require(keccak256(bytes(tokenV1_1.getVersion())) == keccak256(bytes("1.1")), "Version mismatch");
        console2.log("Version after upgrade:", tokenV1_1.getVersion());

        // 7. Unpause engine (if we paused it)
        if (engine.isEnginePaused() && engine.owner() == tokenOwner) {
            console2.log("\n5. Unpausing engine...");
            vm.stopBroadcast();
            vm.startBroadcast(engine.owner());
            engine.unPauseEngine();
            console2.log("Engine unpaused successfully");
        }

        vm.stopBroadcast();

        console2.log("\n=== Token Upgrade Complete ===");
    }
}
