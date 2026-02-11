// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { VestingWalletCliffUpgradeable } from
    "@openzeppelin/contracts-upgradeable/finance/VestingWalletCliffUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title BTvestingCliffWallet
 * @dev Upgradeable vesting wallet with cliff, compatible with OpenZeppelin Clones
 */
contract BTvestingCliffWallet is Initializable, VestingWalletCliffUpgradeable {
    function initialize(
        address beneficiary,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint64 cliffSeconds
    )
        external
        initializer
    {
        __VestingWallet_init(beneficiary, startTimestamp, durationSeconds);
        __VestingWalletCliff_init(cliffSeconds);
    }
}
