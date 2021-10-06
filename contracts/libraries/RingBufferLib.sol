// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

library RingBufferLib {
    /// @notice Returns TWAB index.
    /// @dev `twabs` is a circular buffer of `MAX_CARDINALITY` size equal to 32. So the array goes from 0 to 31.
    /// @dev In order to navigate the circular buffer, we need to use the modulo operator.
    /// @dev For example, if `_index` is equal to 32, `_index % MAX_CARDINALITY` will return 0 and will point to the first element of the array.
    /// @param _index Index used to navigate through `twabs` circular buffer.
    function wrap(uint256 _index, uint256 _cardinality) internal pure returns (uint256) {
        return _index % _cardinality;
    }

    function offset(
        uint256 _index,
        uint256 _amount,
        uint256 _cardinality
    ) internal pure returns (uint256) {
        return (_index + _cardinality - _amount) % _cardinality;
    }

    /// @notice Returns the index of the last recorded TWAB
    /// @param _nextAvailableIndex The next available twab index.  This will be recorded to next.
    /// @param _cardinality The cardinality of the TWAB history.
    /// @return The index of the last recorded TWAB
    function mostRecentIndex(uint256 _nextAvailableIndex, uint256 _cardinality)
        internal
        pure
        returns (uint256)
    {
        if (_cardinality == 0) {
            return 0;
        }

        return (_nextAvailableIndex + _cardinality - 1) % _cardinality;
    }

    function nextIndex(uint256 _currentIndex, uint256 _cardinality)
        internal
        pure
        returns (uint256)
    {
        return (_currentIndex + 1) % _cardinality;
    }
}
