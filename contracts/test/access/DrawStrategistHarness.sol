// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../access/DrawStrategist.sol";

/**
*  @title Abstract ownable contract with additional drawStrategist role
 * @notice Contract module based on Ownable which provides a basic access control mechanism, where
 * there is an account (an draw strategist) that can be granted exclusive access to
 * specific functions.
 *
 * The draw strategist account needs to be set using {setDrawStrategist}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyDrawStrategist`, which can be applied to your functions to restrict their use to
 * the draw strategist.
 */
contract DrawStrategistHarness is DrawStrategist {
    constructor() public {
        __Ownable_init();
    }

    function permissionedCall() public view onlyDrawStrategist returns (string memory) {
        return "isDrawStrategist";
    }
}
