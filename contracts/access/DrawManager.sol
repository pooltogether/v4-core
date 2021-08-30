// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
*  @title Abstract ownable contract with additional drawManager role
 * @notice Contract module based on Ownable which provides a basic access control mechanism, where
 * there is an account (a draw manager) that can be granted exclusive access to
 * specific functions.
 *
 * The draw manager account needs to be set using {setDrawManager}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyDrawManager`, which can be applied to your functions to restrict their use to
 * the draw manager.
 */
abstract contract DrawManager is ContextUpgradeable, OwnableUpgradeable {
    address private _drawManager;

    /**
     * @dev Emitted when _drawManager has been changed.
     * @param previousDrawManager former _drawManager address.
     * @param newDrawManager new _drawManager address.
     */
    event DrawManagerTransferred(address indexed previousDrawManager, address indexed newDrawManager);

    /**
     * @notice Gets current _drawManager.
     * @dev Returns current _drawManager address.
     * @return Current _drawManager address.
     */
    function drawManager() public view virtual returns (address) {
        return _drawManager;
    }

    /**
     * @dev Throws if called by any account other than the draw manager.
     */
    modifier onlyDrawManagerOrOwner() {
        require(drawManager() == _msgSender() || owner() == _msgSender(), "DrawManager/caller-not-draw-manager-or-owner");
        _;
    }

    /**
     * @notice Set or change of draw manager.
     * @dev Throws if called by any account other than the owner.
     * @param _newDrawManager New _drawManager address.
     * @return Boolean to indicate if the operation was successful or not.
     */
    function setDrawManager(address _newDrawManager) public onlyOwner returns (bool) {
        _setDrawManager(_newDrawManager);
    }

    /**
     * @notice Set or change of draw manager.
     * @dev Throws if called by any account other than the owner.
     * @param _newDrawManager New _drawManager address.
     * @return Boolean to indicate if the operation was successful or not.
     */
    function _setDrawManager(address _newDrawManager) internal returns (bool) {
        address _previousDrawManager = _drawManager;
        require(_newDrawManager != address(0), "DrawManager/draw-manager-not-zero-address");
        require(_newDrawManager != _previousDrawManager, "DrawManager/existing-draw-manager-address");

        _drawManager = _newDrawManager;

        emit DrawManagerTransferred(_previousDrawManager, _newDrawManager);
        return true;
    }
}
