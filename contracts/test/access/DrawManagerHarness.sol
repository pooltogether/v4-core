// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../access/DrawManager.sol";

/**
*  @title Abstract ownable contract with additional drawManager role
 * @notice Contract module based on Ownable which provides a basic access control mechanism, where
 * there is an account (an draw manager) that can be granted exclusive access to
 * specific functions.
 *
 * The draw manager account needs to be set using {setDrawManager}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyDrawManager`, which can be applied to your functions to restrict their use to
 * the draw manager.
 */
contract DrawManagerHarness is DrawManager {
    constructor() public {
        __Ownable_init();
    }

    function permissionedCall() public onlyDrawManager returns (string memory) {
        return "isDrawManager";
    }
}
