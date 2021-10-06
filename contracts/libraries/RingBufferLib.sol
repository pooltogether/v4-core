// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

library RingBufferLib {
    /**
    * @notice Returns wrapped TWAB index.
    * @dev  In order to navigate the TWAB circular buffer, we need to use the modulo operator.
    * @dev  For example, if `_index` is equal to 32 and the TWAB circular buffer is of `_cardinality` 32,
    *       it will return 0 and will point to the first element of the array.
    * @param _index Index used to navigate through the TWAB circular buffer.
    * @param _cardinality TWAB buffer cardinality.
    * @return TWAB index.
    */
    function wrap(uint256 _index, uint256 _cardinality) internal pure returns (uint256) {
        return _index % _cardinality;
    }

    /**
    * @notice Returns the `_index` offsetted by `_amount`.
    * @dev  We add `_cardinality` to `_index` to be able to offset event if `_amount` is superior to `_cardinality`.
    * @param _index Index to offset.
    * @param _amount Amount we want to offset the `_index` by.
    * @param _cardinality TWAB buffer cardinality.
    * @return Offsetted index.
     */
    function offset(
        uint256 _index,
        uint256 _amount,
        uint256 _cardinality
    ) internal pure returns (uint256) {
        return wrap(_index + _cardinality - _amount, _cardinality);
    }

    /**
    * @notice Returns index of the last recorded TWAB.
    * @param _nextAvailableIndex Next available twab index to which will be recorded the next TWAB.
    * @param _cardinality TWAB buffer cardinality.
    * @return Index of the last recorded TWAB.
     */
    function mostRecentIndex(uint256 _nextAvailableIndex, uint256 _cardinality)
        internal
        pure
        returns (uint256)
    {
        if (_cardinality == 0) {
            return 0;
        }

        return wrap(_nextAvailableIndex + _cardinality - 1, _cardinality);
    }

    /**
    * @notice Returns the next available TWAB index.
    * @param _currentIndex Current TWAB buffer index.
    * @param _cardinality TWAB buffer cardinality.
    * @return Next available TWAB index.
    */
    function nextIndex(uint256 _currentIndex, uint256 _cardinality)
        internal
        pure
        returns (uint256)
    {
        return wrap(_currentIndex + 1, _cardinality);
    }
}
