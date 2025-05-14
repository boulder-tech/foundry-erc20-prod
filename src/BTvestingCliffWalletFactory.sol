// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IVestingWalletClone {
    function initialize(
        address beneficiary,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint64 cliffSeconds
    )
        external;
}

/**
 * @title BTvestingCliffWalletFactory
 * @notice Factory to create clones of VestingWallet with cliff
 */
contract BTvestingCliffWalletFactory is Ownable {
    ///////////////////
    //    Errors    ///
    ///////////////////

    error BTvestingCliffWalletFactory__AddressCanNotBeZero();
    error InvalidImplementationAddress(address implementation);

    ///////////////////
    //     Types    ///
    ///////////////////

    //////////////////////
    // State Variables ///
    //////////////////////

    address public s_vestingImplementation;

    //////////////////
    //    Events   ///
    //////////////////

    event BTvestingCliffWalletCreated(
        address indexed cloneAddress, address indexed beneficiary, uint64 start, uint64 duration, uint64 cliff
    );

    ///////////////////
    //   Modifiers  ///
    ///////////////////

    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) {
            revert BTvestingCliffWalletFactory__AddressCanNotBeZero();
        }
        _;
    }

    ///////////////////
    //   Functions  ///
    ///////////////////

    constructor(address _implementation) Ownable(msg.sender) {
        require(_implementation != address(0), "Invalid implementation address");
        s_vestingImplementation = _implementation;
    }

    /*
     * @notice Update the implementation address
     * @param newImplementation The new implementation address
     */
    function updateImplementation(address newImplementation) external onlyOwner nonZeroAddress(newImplementation) {
        s_vestingImplementation = newImplementation;
    }

    /*
     * @notice Create a new vesting wallet clone
     * @param beneficiary The address of the beneficiary
     * @param startTimestamp The start timestamp of the vesting period
     * @param durationSeconds The duration of the vesting period in seconds
     * @param cliffSeconds The cliff period in seconds
     * @return clone The address of the newly created vesting wallet clone
     */
    function createVestingWallet(
        address beneficiary,
        uint64 startTimestamp,
        uint64 durationSeconds,
        uint64 cliffSeconds
    )
        external
        onlyOwner
        nonZeroAddress(beneficiary)
        nonZeroAddress(s_vestingImplementation)
        returns (address clone)
    {
        clone = Clones.clone(s_vestingImplementation);

        IVestingWalletClone(clone).initialize(beneficiary, startTimestamp, durationSeconds, cliffSeconds);

        emit BTvestingCliffWalletCreated(clone, beneficiary, startTimestamp, durationSeconds, cliffSeconds);
    }
}
