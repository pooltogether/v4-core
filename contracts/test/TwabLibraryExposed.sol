// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../libraries/TwabLibrary.sol";
import "../libraries/RingBuffer.sol";

/// @title OverflowSafeComparator library to share comparator functions between contracts
/// @author PoolTogether Inc.
contract TwabLibraryExposed {
  uint16 public constant MAX_CARDINALITY = 65535;

  using TwabLibrary for ObservationLib.Observation[MAX_CARDINALITY];

  ObservationLib.Observation[MAX_CARDINALITY] internal twabs;

  function setTwabs(ObservationLib.Observation[] calldata _twabs) external {
    for (uint256 i = 0; i < _twabs.length; i++) {
      twabs[i] = _twabs[i];
      if (_twabs[i].timestamp == 0) {
        twabs[i].timestamp = uint32(block.timestamp);
      }
    }
  }

/*
  function wrapCardinality(uint256 _index, uint16 _cardinality) external pure returns (uint16) {
    return uint16(RingBuffer.wrap(_index, _cardinality));
  }

  function mostRecentIndex(uint256 _nextAvailableIndex, uint16 _cardinality) external pure returns (uint16) {
    return uint16(RingBuffer.mostRecentIndex(_nextAvailableIndex, _cardinality));
  }

  function calculateTwab(
    ObservationLib.Observation memory newestTwab,
    ObservationLib.Observation memory oldestTwab,
    uint16 _twabIndex,
    uint16 _oldestTwabIndex,
    uint32 _targetTimestamp,
    uint224 _currentBalance,
    uint16 _cardinality,
    uint32 _currentTimestamp
  ) external view returns (ObservationLib.Observation memory) {
    return twabs.calculateTwab(newestTwab, oldestTwab, _twabIndex, _oldestTwabIndex, _targetTimestamp, _currentBalance, _cardinality, _currentTimestamp);
  }

  function getAverageBalanceBetween(
    uint224 _currentBalance,
    uint16 _twabIndex,
    uint32 _startTime,
    uint32 _endTime,
    uint16 _cardinality,
    uint32 _time
  ) external view returns (uint256) {
    return twabs.getAverageBalanceBetween(_currentBalance, _twabIndex, _startTime, _endTime, _cardinality, _time);
  }

  /// @notice Retrieves amount at `_target` timestamp
  /// @param _currentBalance Most recent amount recorded.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @param _twabIndex Most recent TWAB index recorded.
  /// @return uint256 TWAB amount at `_target`.
  function getBalanceAt(
    uint32 _target,
    uint256 _currentBalance,
    uint16 _twabIndex,
    uint16 _cardinality,
    uint32 _currentTimestamp
  ) external view returns (uint256) {
    return twabs.getBalanceAt(_target, _currentBalance, _twabIndex, _cardinality, _currentTimestamp);
  }

  /// @notice Records a new TWAB.
  /// @param _currentBalance Current `amount`.
  /// @return New TWAB that was recorded.
  function nextTwab(
    ObservationLib.Observation memory _currentTwab,
    uint256 _currentBalance,
    uint32 _currentTimestamp
  ) external view returns (ObservationLib.Observation memory) {
    return TwabLibrary.nextTwab(_currentTwab, _currentBalance, _currentTimestamp);
  }

  function calculateNextWithExpiry(
    uint16 _nextTwabIndex,
    uint16 _cardinality,
    uint32 _time,
    uint32 _expiry
  ) internal view returns (uint16 nextAvailableTwabIndex, uint16 nextCardinality) {
    return twabs.calculateNextWithExpiry(_nextTwabIndex, _cardinality, _time, _expiry);
  }

  function nextTwabWithExpiry(
    uint224 _balance,
    uint224 _newBalance,
    uint16 _nextTwabIndex,
    uint16 _cardinality,
    uint32 _time,
    uint32 _maxLifetime
  ) internal returns (uint16 nextAvailableTwabIndex, uint16 nextCardinality, ObservationLib.Observation memory twab, bool isNew) {
    return twabs.nextTwabWithExpiry(_balance, _nextTwabIndex, _cardinality, _time, _maxLifetime);
  }
  */
}
