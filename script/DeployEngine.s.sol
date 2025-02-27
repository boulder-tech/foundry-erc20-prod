// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script, console, console2 } from "forge-std/Script.sol";
import { BTtokensEngine } from "../src/BTtokensEngine.sol";
import { BTtokens } from "../src/BTtokens.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployEngine is Script {
    function run() external returns (address, address) {
        (address proxyEngine, address tokenImplementationAddress) = deployBTtokensEngine();
        return (proxyEngine, tokenImplementationAddress);
    }

    function deployBTtokensEngine() public returns (address, address) {
        vm.startBroadcast();
        BTtokensEngine engine = new BTtokensEngine(); // Implementation (the logic)
        ERC1967Proxy proxyEngine = new ERC1967Proxy(address(engine), "");
        // new ERC1967Proxy(address(engine), abi.encodeWithSignature("initialize(address)", address(this))); // ¿No
        // debería enviar el initialOwner en algún lado? - si lo hago en el test para inicializarlo!!
        BTtokens tokenImplementation = new BTtokens();
        vm.stopBroadcast();
        return (address(proxyEngine), address(tokenImplementation));
    }
}
