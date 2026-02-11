// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console, console2 } from "forge-std/Script.sol";
import { BTtokensEngine_v1 } from "../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokens_v1 } from "../src/BTContracts/v1.0/BTtokens_v1.sol";
import { BTtokensManager } from "../src/BTContracts/v1.0/BTtokensManager.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployEngine is Script {
    function run(address initialAdmin) external returns (address, address, address) {
        (address proxyEngine, address tokenImplementationAddress, address tokenManagerAddress) =
            deployBTtokensEngine(initialAdmin);
        return (proxyEngine, tokenImplementationAddress, tokenManagerAddress);
    }

    function deployBTtokensEngine(address initialAdmin) public returns (address, address, address) {
        vm.startBroadcast();
        BTtokensEngine_v1 engine = new BTtokensEngine_v1(); // Implementation (the logic)
        ERC1967Proxy proxyEngine = new ERC1967Proxy(address(engine), "");
        // Proxy is initialized in tests via engine.initialize(owner, tokenImpl, accessManager)
        BTtokens_v1 tokenImplementation = new BTtokens_v1();
        BTtokensManager tokenManager = new BTtokensManager(initialAdmin);
        vm.stopBroadcast();
        return (address(proxyEngine), address(tokenImplementation), address(tokenManager));
    }
}
