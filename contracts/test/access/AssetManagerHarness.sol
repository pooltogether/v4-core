// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../access/AssetManager.sol";

/**
*  @title Abstract ownable contract with additional assetManager role
 * @notice Contract module based on Ownable which provides a basic access control mechanism, where
 * there is an account (an asset manager) that can be granted exclusive access to
 * specific functions.
 *
 * The asset manager account needs to be set using {setAssetManager}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyAssetManager`, which can be applied to your functions to restrict their use to
 * the asset manager.
 */
contract AssetManagerHarness is AssetManager {
    constructor() public {
        __Ownable_init();
    }

    function permissionedCall() public onlyAssetManager returns (string memory) {
        return "isAssetManager";
    }
}
