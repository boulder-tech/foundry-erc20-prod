// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import { BTvestingCliffWallet } from "../src/BTvestingCliffWallet.sol";
import { BTvestingCliffWalletFactory } from "../src/BTvestingCliffWalletFactory.sol";

contract DeployVesting is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        vm.startBroadcast(deployer);

        // 1. Deploy vesting implementation
        BTvestingCliffWallet vestingImplementation = new BTvestingCliffWallet();

        // 2. Deploy factory
        BTvestingCliffWalletFactory factory = new BTvestingCliffWalletFactory(address(vestingImplementation));

        console2.log("Vesting Implementation:", address(vestingImplementation));
        console2.log("Vesting Factory:", address(factory));

        vm.stopBroadcast();
    }
}
