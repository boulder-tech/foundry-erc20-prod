// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import { AccessManager } from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title BTtokensManager
 * @author Openzeppelin
 * @notice The initialAdmin should be the BTtokensEngine contract
 */
contract BTtokensManager is AccessManager {
    address private s_initialAdmin;

    constructor(address initialAdmin) AccessManager(initialAdmin) {
        if (initialAdmin == address(0)) {
            revert AccessManagerInvalidInitialAdmin(address(0));
        }
        s_initialAdmin = initialAdmin;
        // admin is active immediately and without any execution delay.
        _grantRole(ADMIN_ROLE, s_initialAdmin, 0, 0);
    }
}
