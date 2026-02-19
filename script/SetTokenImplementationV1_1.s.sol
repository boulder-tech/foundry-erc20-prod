// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { BTtokensEngine_v1 } from "../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { BTtokens_v1 } from "../src/BTContracts/v1.1/BTtokens_v1.sol";

/**
 * @title SetTokenImplementationV1_1
 * @notice Script to deploy token v1.1 implementation and set it in the engine.
 * @dev This should be run AFTER upgrading the engine to v1.1.
 *      This ensures new tokens created will use v1.1 implementation.
 * 
 * Usage:
 *   forge script script/SetTokenImplementationV1_1.s.sol:SetTokenImplementationV1_1 \
 *     --rpc-url $BASE_SEPOLIA_RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     --etherscan-api-key $BASESCAN_API_KEY \
 *     -vvvv
 */
contract SetTokenImplementationV1_1 is Script {
    address public engineProxy;
    address public owner;

    function setUp() public {
        try vm.envAddress("ENGINE_PROXY") returns (address proxy) {
            engineProxy = proxy;
        } catch {
            engineProxy = address(0);
        }
        try vm.envAddress("ENGINE_OWNER") returns (address envOwner) {
            owner = envOwner;
        } catch {
            owner = msg.sender;
        }
    }

    function run() external {
        require(engineProxy != address(0), "ENGINE_PROXY must be set (export ENGINE_PROXY=0x...)");
        
        console2.log("=== Set Token Implementation v1.1 ===");
        console2.log("Engine Proxy:", engineProxy);
        console2.log("Owner:", owner);

        vm.startBroadcast(owner);

        // 1. Verify engine is v1.1
        BTtokensEngine_v1 engine = BTtokensEngine_v1(engineProxy);
        require(keccak256(bytes(engine.getVersion())) == keccak256(bytes("1.1")), "Engine must be v1.1");
        console2.log("\n1. Engine version verified:", engine.getVersion());

        // 2. Deploy token v1.1 implementation
        console2.log("\n2. Deploying token v1.1 implementation...");
        BTtokens_v1 tokenV1_1Implementation = new BTtokens_v1();
        console2.log("Token v1.1 Implementation:", address(tokenV1_1Implementation));

        // 3. Verify current implementation
        address currentImpl = engine.s_tokenImplementationAddress();
        console2.log("Current token implementation:", currentImpl);
        require(currentImpl != address(tokenV1_1Implementation), "Implementation already set");

        // 4. Pause engine (required for setNewTokenImplementationAddress)
        console2.log("\n3. Pausing engine...");
        require(!engine.isEnginePaused(), "Engine is already paused");
        engine.pauseEngine();
        require(engine.isEnginePaused(), "Engine pause failed");
        console2.log("Engine paused successfully");

        // 5. Set new implementation
        console2.log("\n4. Setting new token implementation...");
        engine.setNewTokenImplementationAddress(address(tokenV1_1Implementation));
        require(engine.s_tokenImplementationAddress() == address(tokenV1_1Implementation), "Implementation not set");
        console2.log("New token implementation set:", address(tokenV1_1Implementation));

        // 6. Unpause engine
        console2.log("\n5. Unpausing engine...");
        engine.unPauseEngine();
        require(!engine.isEnginePaused(), "Engine unpause failed");
        console2.log("Engine unpaused successfully");

        vm.stopBroadcast();

        console2.log("\n=== Setup Complete ===");
        console2.log("New tokens created will now use v1.1 implementation");
    }
}
