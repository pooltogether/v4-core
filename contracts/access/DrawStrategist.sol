// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
*  @title Abstract ownable contract with additional drawStrategist role
 * @notice Contract module based on Ownable which provides a basic access control mechanism, where
 * there is an account (a draw strategist) that can be granted exclusive access to
 * specific functions.
 *
 * The draw strategist account needs to be set using {setDrawStrategist}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyDrawStrategist`, which can be applied to your functions to restrict their use to
 * the draw strategist.
 */
abstract contract DrawStrategist is ContextUpgradeable, OwnableUpgradeable {
    address private _drawStrategist;

    /**
     * @dev Emitted when _drawStrategist has been changed.
     * @param previousDrawStrategist former _drawStrategist address.
     * @param newDrawStrategist new _drawStrategist address.
     */
    event DrawStrategistTransferred(address indexed previousDrawStrategist, address indexed newDrawStrategist);

    /**
     * @notice Gets current _drawStrategist.
     * @dev Returns current _drawStrategist address.
     * @return Current _drawStrategist address.
     */
    function drawStrategist() public view virtual returns (address) {
        return _drawStrategist;
    }

    /**
     * @dev Throws if called by any account other than the draw strategist.
     */
    modifier onlyDrawStrategist() {
        require(drawStrategist() == _msgSender(), "DrawStrategist/caller-not-drawStrategist");
        _;
    }

    /**
     * @notice Set or change of draw strategist.
     * @dev Throws if called by any account other than the owner.
     * @param _newDrawStrategist New _drawStrategist address.
     * @return Boolean to indicate if the operation was successful or not.
     */
    function setDrawStrategist(address _newDrawStrategist) public virtual onlyOwner returns (bool) {
        address _previousDrawStrategist = _drawStrategist;

        require(_newDrawStrategist != address(0), "DrawStrategist/drawStrategist-not-zero-address");
        require(_newDrawStrategist != _previousDrawStrategist, "DrawStrategist/existing-drawStrategist-address");

        _drawStrategist = _newDrawStrategist;

        emit DrawStrategistTransferred(_previousDrawStrategist, _newDrawStrategist);
        return true;
    }
}
