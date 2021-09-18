// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./OverflowSafeComparator.sol";
import "./RingBuffer.sol";

/// @title Time-Weighted Average Balance Library
/// @notice This library allows you to efficiently track a user's historic balance.  You can get a
/// @author PoolTogether Inc.
library TwabLibrary {
  using OverflowSafeComparator for uint32;
  using SafeCast for uint256;

  /// @notice The maximum number of twab entries
  uint16 public constant MAX_CARDINALITY = 65535;

  /// @notice Time Weighted Average Balance (TWAB).
  /// @param amount `amount` at `timestamp`.
  /// @param timestamp Recorded `timestamp`.
  struct Twab {
    uint224 amount;
    uint32 timestamp;
  }

  /// @notice Ensures the passed cardinality is a minimum of 1
  /// @param _cardinality The cardinality to ensure a floor of 1
  /// @return Returns 1 if the given cardinality is zero, otherwise return the cardinality
  function _minCardinality(uint16 _cardinality) internal pure returns (uint16) {
    return _cardinality > 0 ? _cardinality : 1;
  }

  /// @notice Retrieves TWAB balance.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalanceAt(
    uint16 _cardinality,
    uint16 _nextTwabIndex,
    Twab[MAX_CARDINALITY] storage _twabs,
    uint224 _balance,
    uint32 _target,
    uint32 _time
  ) internal view returns (uint256) {
    uint16 cardinality = _minCardinality(_cardinality);
    uint16 recentIndex = uint16(RingBuffer.mostRecentIndex(_nextTwabIndex, cardinality));
    return getBalanceAt(_twabs, _target, _balance, recentIndex, cardinality, _time);
  }

  /// @notice Calculates the average balance held by an Account for a given time frame.
  /// @param _startTime The start time of the time frame.
  /// @param _endTime The end time of the time frame.
  /// @param _time The current time
  /// @return The average balance that the user held during the time frame.
  function getAverageBalanceBetween(
    uint16 _cardinality,
    uint16 _nextTwabIndex,
    Twab[MAX_CARDINALITY] storage _twabs,
    uint224 _balance,
    uint32 _startTime,
    uint32 _endTime,
    uint32 _time
  ) internal view returns (uint256) {
    uint16 card = _minCardinality(_cardinality);
    uint16 recentIndex = uint16(RingBuffer.mostRecentIndex(_nextTwabIndex, card));
    return getAverageBalanceBetween(
      _twabs,
      _balance,
      recentIndex,
      _startTime,
      _endTime,
      card,
      _time
    );
  }

  /// @notice Decreases an account's balance and records a new twab.
  /// @param _balance The balance held since the last update
  /// @param _time The current time
  /// @param _ttl The time-to-live for TWABs. This is essentially how long twabs are kept around.  History is not available longer than the time-to-live.
  /// @return nextTwabIndex
  /// @return cardinality
  /// @return twab The user's latest TWAB
  /// @return isNew Whether the TWAB is new
  function update(
    uint224 _balance,
    uint16 _nextTwabIndex,
    uint16 _cardinality,
    Twab[MAX_CARDINALITY] storage _twabs,
    uint32 _time,
    uint32 _ttl
  ) internal returns (uint16 nextTwabIndex, uint16 cardinality, Twab memory twab, bool isNew) {
    (nextTwabIndex, cardinality, twab, isNew) = nextTwabWithExpiry(
      _twabs,
      _balance,
      _nextTwabIndex,
      _cardinality,
      _time,
      _ttl
    );
  }

  /// @dev A struct that just used internally to bypass the stack variable limitation
  struct AvgHelper {
    uint16 twabIndex;
    uint16 oldestTwabIndex;
    uint32 startTime;
    uint32 endTime;
    uint16 cardinality;
  }

  /// @notice Fetches TWABs `beforeOrAt` and `atOrAfter` a `_target`, eg: where [`beforeOrAt`, `atOrAfter`] is satisfied.
  /// The result may be the same TWAB, or adjacent TWABs.
  /// @dev The answer must be contained in the array, used when the target is located within the stored TWAB.
  /// boundaries: older than the most recent TWAB and younger, or the same age as, the oldest TWAB.
  /// @param _twabs List of TWABs to search through.
  /// @param _twabIndex Index of the TWAB to start searching from.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @return beforeOrAt TWAB recorded before, or at, the target.
  /// @return atOrAfter TWAB recorded at, or after, the target.
  function binarySearch(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint16 _twabIndex,
    uint16 _oldestTwabIndex,
    uint32 _target,
    uint16 _cardinality,
    uint32 _time
  ) internal view returns (Twab memory beforeOrAt, Twab memory atOrAfter) {
    uint256 leftSide = _oldestTwabIndex; // Oldest TWAB
    uint256 rightSide = _twabIndex < leftSide ? leftSide + _cardinality - 1 : _twabIndex;
    uint256 currentIndex;

    while (true) {
      currentIndex = (leftSide + rightSide) / 2;
      beforeOrAt = _twabs[uint16(RingBuffer.wrap(currentIndex, _cardinality))];
      uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

      // We've landed on an uninitialized timestamp, keep searching higher (more recently)
      if (beforeOrAtTimestamp == 0) {
        leftSide = currentIndex + 1;
        continue;
      }

      atOrAfter = _twabs[uint16(RingBuffer.nextIndex(currentIndex, _cardinality))];

      bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, _time);

      // Check if we've found the corresponding TWAB
      if (targetAtOrAfter && _target.lte(atOrAfter.timestamp, _time)) {
        break;
      }

      // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
      if (!targetAtOrAfter) rightSide = currentIndex - 1;

      // Otherwise, we keep searching higher
      else leftSide = currentIndex + 1;
    }
  }

  /// @notice Calculates the TWAB for a given timestamp.  It interpolates as necessary.
  /// @param _twabs The TWAB history
  function calculateTwab(
    Twab[MAX_CARDINALITY] storage _twabs,
    Twab memory newestTwab,
    Twab memory oldestTwab,
    uint16 _twabIndex,
    uint16 _oldestTwabIndex,
    uint32 targetTimestamp,
    uint224 _currentBalance,
    uint16 _cardinality,
    uint32 _time
  ) internal view returns (Twab memory) {
    // If `targetTimestamp` is chronologically after the newest TWAB, we extrapolate a new one
    if (newestTwab.timestamp.lt(targetTimestamp, _time)) {
      return Twab({
        amount: newestTwab.amount + _currentBalance*(targetTimestamp - newestTwab.timestamp),
        timestamp: targetTimestamp
      });
    }

    if (newestTwab.timestamp == targetTimestamp) {
      return newestTwab;
    }

    if (oldestTwab.timestamp == targetTimestamp) {
      return oldestTwab;
    }

    // If `targetTimestamp` is chronologically before the oldest TWAB, we create a zero twab
    if (targetTimestamp.lt(oldestTwab.timestamp, _time)) {
      return Twab({
        amount: 0,
        timestamp: targetTimestamp
      });
    }

    // Otherwise, both timestamps must be surrounded by twabs.
    (
      Twab memory beforeOrAtStart,
      Twab memory afterOrAtStart
    ) = binarySearch(_twabs, _twabIndex, _oldestTwabIndex, targetTimestamp, _cardinality, _time);

    uint224 heldBalance = (afterOrAtStart.amount - beforeOrAtStart.amount) / (afterOrAtStart.timestamp - beforeOrAtStart.timestamp);
    uint224 amount = beforeOrAtStart.amount + heldBalance * (targetTimestamp - beforeOrAtStart.timestamp);

    return Twab({
      amount: amount,
      timestamp: targetTimestamp
    });
  }

  function getAverageBalanceBetween(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint224 _currentBalance,
    uint16 _twabIndex,
    uint32 _startTime,
    uint32 _endTime,
    uint16 _cardinality,
    uint32 _time
  ) internal view returns (uint256) {
    require(_endTime > _startTime, "TWAB/startTime-gt-than-endTime");

    // Find oldest Twab
    uint16 oldestTwabIndex = uint16(RingBuffer.nextIndex(_twabIndex, _cardinality));
    Twab memory oldestTwab = _twabs[oldestTwabIndex];
    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (oldestTwab.timestamp == 0) {
      oldestTwabIndex = 0;
      oldestTwab = _twabs[0];
    }

    return _getAverageBalanceBetween(
      _twabs,
      _currentBalance,
      AvgHelper({
        twabIndex: _twabIndex,
        oldestTwabIndex: oldestTwabIndex,
        startTime: _startTime,
        endTime: _endTime,
        cardinality: _cardinality
      }),
      oldestTwab,
      _time
    );
  }

  function _getAverageBalanceBetween(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint224 _currentBalance,
    AvgHelper memory helper,
    Twab memory _oldestTwab,
    uint32 _time
  ) private view returns (uint256) {
    uint32 endTime = helper.endTime > _time ? _time : helper.endTime;

    Twab memory newestTwab = _twabs[helper.twabIndex];

    Twab memory startTwab = calculateTwab(
      _twabs, newestTwab, _oldestTwab, helper.twabIndex, helper.oldestTwabIndex, helper.startTime, _currentBalance, helper.cardinality, _time
    );
    Twab memory endTwab = calculateTwab(
      _twabs, newestTwab, _oldestTwab, helper.twabIndex, helper.oldestTwabIndex, endTime, _currentBalance, helper.cardinality, _time
    );

    // Difference in amount / time
    return (endTwab.amount - startTwab.amount) / (endTwab.timestamp - startTwab.timestamp);
  }

  /// @notice Retrieves amount at `_target` timestamp
  /// @param _twabs List of TWABs to search through.
  /// @param _currentBalance Most recent amount recorded.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @param _twabIndex Most recent TWAB index recorded.
  /// @return uint256 TWAB amount at `_target`.
  function getBalanceAt(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint32 _target,
    uint256 _currentBalance,
    uint16 _twabIndex,
    uint16 _cardinality,
    uint32 _time
  ) internal view returns (uint256) {
    uint32 targetTimestamp = _target > _time ? _time : _target;

    Twab memory afterOrAt;
    Twab memory beforeOrAt = _twabs[_twabIndex];

    // If `targetTimestamp` is chronologically after the newest TWAB, we can simply return the current balance
    if (beforeOrAt.timestamp.lte(targetTimestamp, _time)) {
      return _currentBalance;
    }

    // Now, set before to the oldest TWAB
    uint16 oldestTwabIndex = uint16(RingBuffer.nextIndex(_twabIndex, _cardinality));
    beforeOrAt = _twabs[oldestTwabIndex];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (beforeOrAt.timestamp == 0) {
      oldestTwabIndex = 0;
      beforeOrAt = _twabs[0];
    }

    // If `targetTimestamp` is chronologically before the oldest TWAB, we can early return
    if (targetTimestamp.lt(beforeOrAt.timestamp, _time)) {
      return 0;
    }

    // Otherwise, we perform the `binarySearch`
    (beforeOrAt, afterOrAt) = binarySearch(_twabs, _twabIndex, oldestTwabIndex, _target, _cardinality, _time);

    // Difference in amount / time
    uint224 differenceInAmount = afterOrAt.amount - beforeOrAt.amount;
    uint32 differenceInTime = afterOrAt.timestamp - beforeOrAt.timestamp;

    return differenceInAmount / differenceInTime;
  }

  /// @notice Records a new TWAB.
  /// @param _currentBalance Current `amount`.
  /// @return New TWAB that was recorded.
  function nextTwab(
    Twab memory _currentTwab,
    uint256 _currentBalance,
    uint32 _time
  ) internal pure returns (Twab memory) {
    // New twab amount = last twab amount (or zero) + (current amount * elapsed seconds)
    return Twab({
      amount: (uint256(_currentTwab.amount) + (_currentBalance * (_time.checkedSub(_currentTwab.timestamp, _time)))).toUint224(),
      timestamp: _time
    });
  }

  function calculateNextWithExpiry(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint16 _nextTwabIndex,
    uint16 _cardinality,
    uint32 _time,
    uint32 _ttl
  ) internal view returns (uint16 nextAvailableTwabIndex, uint16 nextCardinality) {
    uint16 cardinality = _cardinality > 0 ? _cardinality : 1;
/*
    TTL: 100

    Example 1:
      next twab timestamp: 100

      existing twab timestamps:
      0: 10
      1: 90

      we should not eliminate 0 or else the history will be 10 seconds long

    Example 2:

      next twab timestamp: 105

      existing twab timestamps
      0: 1
      1: 5

      We can eliminate 0, because the history will be 100 seconds long

    Q: when do we eliminate the oldest twab?
    A: when current time - second oldest twab >= time to live
    */

    Twab memory secondOldestTwab;
    // if there are two or more records (cardinality is always one greater than # of records)
    if (cardinality > 2) {
      // get the second oldest twab
      secondOldestTwab = _twabs[uint16(RingBuffer.nextIndex(_nextTwabIndex, cardinality))];
    }

    nextCardinality = cardinality;
    if (secondOldestTwab.timestamp == 0 || _time.checkedSub(secondOldestTwab.timestamp, _time) < _ttl) {
      nextCardinality = cardinality < MAX_CARDINALITY ? cardinality + 1 : MAX_CARDINALITY;
    }

    nextAvailableTwabIndex = uint16(RingBuffer.nextIndex(_nextTwabIndex, nextCardinality));
  }

  function nextTwabWithExpiry(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint224 _balance,
    uint16 _nextTwabIndex,
    uint16 _cardinality,
    uint32 _time,
    uint32 _maxLifetime
  ) internal returns (uint16 nextAvailableTwabIndex, uint16 nextCardinality, Twab memory twab, bool isNew) {
    Twab memory newestTwab = _twabs[uint16(RingBuffer.mostRecentIndex(_nextTwabIndex, _cardinality))];

    // if we're in the same block, return
    if (newestTwab.timestamp == _time) {
      return (_nextTwabIndex, _cardinality, newestTwab, false);
    }

    (nextAvailableTwabIndex, nextCardinality) = calculateNextWithExpiry(_twabs, _nextTwabIndex, _cardinality, _time, _maxLifetime);

    Twab memory newTwab = nextTwab(
      newestTwab,
      _balance,
      _time
    );

    _twabs[_nextTwabIndex] = newTwab;

    return (nextAvailableTwabIndex, nextCardinality, newTwab, true);
  }
}
