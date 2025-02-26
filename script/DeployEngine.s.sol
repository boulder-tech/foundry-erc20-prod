// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console, console2 } from "forge-std/Script.sol";
import { BTtokensEngine } from "../src/BTtokensEngine.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployEngine is Script {
    function run() external returns (address) {
        address proxy = deployBTtokensEngine();
        return proxy;
    }

    function deployBTtokensEngine() public returns (address) {
        vm.startBroadcast();
        BTtokensEngine engine = new BTtokensEngine(); // Implementation (the logic)
        ERC1967Proxy proxy = new ERC1967Proxy(address(engine), "");
        // new ERC1967Proxy(address(engine), abi.encodeWithSignature("initialize(address)", address(this))); // ¿No
        // debería enviar el initialOwner en algún lado?
        vm.stopBroadcast();
        return address(proxy);
    }
}
