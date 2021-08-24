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
    modifier onlyDrawManager() {
        require(drawManager() == _msgSender(), "drawManager/caller-not-draw-manager");
        _;
    }

    /**
     * @notice Set or change of draw manager.
     * @dev Throws if called by any account other than the owner.
     * @param _newDrawManager New _drawManager address.
     * @return Boolean to indicate if the operation was successful or not.
     */
    function setDrawManager(address _newDrawManager) public virtual onlyOwner returns (bool) {
        require(_newDrawManager != address(0), "drawManager/drawManager-not-zero-address");

        address _previousDrawManager = _drawManager;
        _drawManager = _newDrawManager;

        emit DrawManagerTransferred(_previousDrawManager, _newDrawManager);
        return true;
    }
}
