// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { BTtokensEngine_v1 } from "../src/BTContracts/v1.0/BTtokensEngine_v1.sol";

/**
 * @title CreateToken
 * @notice Creates one token v1.0 via the engine (for local testing before upgrade).
 * @dev Engine must be v1.0 and initialized. Run after DeployAndInitEngine.
 *      Export ENGINE_PROXY; then export TOKEN_PROXY from this script output for UpgradeTokenToV1_1.
 *
 * Usage (local):
 *   export ENGINE_PROXY=0x...
 *   forge script script/CreateToken.s.sol:CreateToken \
 *     --rpc-url http://localhost:8545 \
 *     --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
 *     --broadcast
 */
contract CreateToken is Script {
    string public constant TOKEN_NAME = "BoulderTestToken";
    string public constant TOKEN_SYMBOL = "BTT";
    uint8 public constant TOKEN_DECIMALS = 6;

    address public engineProxy;
    address public owner;

    function setUp() public {
        try vm.envAddress("ENGINE_PROXY") returns (address proxy) {
            engineProxy = proxy;
        } catch {
            engineProxy = address(0);
        }
        owner = msg.sender;
    }

    function run() external {
        require(engineProxy != address(0), "ENGINE_PROXY must be set (export ENGINE_PROXY=0x...)");

        address manager = BTtokensEngine_v1(engineProxy).s_accessManagerAddress();
        bytes memory data = abi.encode(
            engineProxy,
            manager,
            owner,
            owner,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );

        vm.startBroadcast(owner);
        address tokenProxy = BTtokensEngine_v1(engineProxy).createToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            data,
            owner,
            owner
        );
        vm.stopBroadcast();

        console2.log("\n=== Token v1.0 created ===");
        console2.log("Token Proxy:", tokenProxy);
        console2.log("\nExport for token upgrade (after engine + set token impl):");
        console2.log("  export TOKEN_PROXY=", tokenProxy);
    }
}
