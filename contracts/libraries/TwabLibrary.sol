// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "hardhat/console.sol";

import "./OverflowSafeComparator.sol";

/// @title OverflowSafeComparator library to share comparator functions between contracts
/// @author PoolTogether Inc.
library TwabLibrary {
  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;

  uint16 public constant MAX_CARDINALITY = 65535;

  /// @notice Time Weighted Average Balance (TWAB).
  /// @param amount `amount` at `timestamp`.
  /// @param timestamp Recorded `timestamp`.
  struct Twab {
    uint224 amount;
    uint32 timestamp;
  }

  /// @dev A struct that just used internally to bypass the stack variable limitation
  struct AvgHelper {
    uint16 twabIndex;
    uint16 oldestTwabIndex;
    uint32 startTime;
    uint32 endTime;
    uint16 cardinality;
  }

  /// @notice Returns TWAB index.
  /// @dev `twabs` is a circular buffer of `MAX_CARDINALITY` size equal to 32. So the array goes from 0 to 31.
  /// @dev In order to navigate the circular buffer, we need to use the modulo operator.
  /// @dev For example, if `_index` is equal to 32, `_index % MAX_CARDINALITY` will return 0 and will point to the first element of the array.
  /// @param _index Index used to navigate through `twabs` circular buffer.
  function wrapCardinality(uint256 _index, uint16 _cardinality) internal pure returns (uint16) {
    return uint16(_index % _cardinality);
  }

  function mostRecentIndex(uint256 _nextAvailableIndex, uint16 _cardinality) internal pure returns (uint16) {
    return wrapCardinality(_nextAvailableIndex + uint256(_cardinality) - 1, _cardinality);
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
  function _binarySearch(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint16 _twabIndex,
    uint16 _oldestTwabIndex,
    uint32 _target,
    uint16 _cardinality
  ) internal view returns (Twab memory beforeOrAt, Twab memory atOrAfter) {
    uint32 time = uint32(block.timestamp);
    uint256 leftSide = _oldestTwabIndex; // Oldest TWAB
    uint256 rightSide = _twabIndex < leftSide ? leftSide + _cardinality - 1 : _twabIndex;
    uint256 currentIndex;

    while (true) {
      currentIndex = (leftSide + rightSide) / 2;
      beforeOrAt = _twabs[wrapCardinality(currentIndex, _cardinality)];
      uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

      // console.log("leftSide: ", leftSide);
      // console.log("currentIndex: ", currentIndex);
      // console.log("rightSide: ", rightSide);

      // console.log("_target: ", _target);
      // console.log("beforeOrAtTimestamp: ", beforeOrAtTimestamp);

      // We've landed on an uninitialized timestamp, keep searching higher (more recently)
      if (beforeOrAtTimestamp == 0) {
        leftSide = currentIndex + 1;
        continue;
      }

      atOrAfter = _twabs[wrapCardinality(currentIndex + 1, _cardinality)];

      bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, time);

      
      // console.log("atOrAfter.timestamp: ", atOrAfter.timestamp);

      // Check if we've found the corresponding TWAB
      if (targetAtOrAfter && _target.lt(atOrAfter.timestamp, time)) {
        break;
      }

      // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
      if (!targetAtOrAfter) rightSide = currentIndex - 1;

      // Otherwise, we keep searching higher
      else leftSide = currentIndex + 1;
    }
  }

  function calculateTwab(
    Twab[MAX_CARDINALITY] storage _twabs,
    Twab memory newestTwab,
    Twab memory oldestTwab,
    uint16 _twabIndex,
    uint16 _oldestTwabIndex,
    uint32 targetTimestamp,
    uint224 _currentBalance,
    uint16 _cardinality
  ) internal view returns (Twab memory) {
    uint32 time = uint32(block.timestamp);
    // If `targetTimestamp` is chronologically after the newest TWAB, we extrapolate a new one
    if (newestTwab.timestamp.lt(targetTimestamp, time)) {
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
    if (targetTimestamp.lt(oldestTwab.timestamp, time)) {
      return Twab({
        amount: 0,
        timestamp: targetTimestamp
      });
    }

    // Otherwise, both timestamps must be surrounded by twabs.
    (Twab memory beforeOrAtStart, Twab memory afterOrAtStart) = _binarySearch(_twabs, _twabIndex, _oldestTwabIndex, targetTimestamp, _cardinality);

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
    uint16 _cardinality
  ) internal view returns (uint256) {
    require(_endTime > _startTime, "start time must be greater than end time");

    // Find oldest Twab
    uint16 oldestTwabIndex = wrapCardinality(_twabIndex + 1, _cardinality);
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
      oldestTwab
    );
  }

  function _getAverageBalanceBetween(
    Twab[MAX_CARDINALITY] storage _twabs,
    uint224 _currentBalance,
    AvgHelper memory helper,
    Twab memory _oldestTwab
  ) internal view returns (uint256) {
    uint32 time = uint32(block.timestamp);
    uint32 endTime = helper.endTime > time ? time : helper.endTime;

    Twab memory newestTwab = _twabs[helper.twabIndex];

    Twab memory startTwab = calculateTwab(_twabs, newestTwab, _oldestTwab, helper.twabIndex, helper.oldestTwabIndex, helper.startTime, _currentBalance, helper.cardinality);
    Twab memory endTwab = calculateTwab(_twabs, newestTwab, _oldestTwab, helper.twabIndex, helper.oldestTwabIndex, endTime, _currentBalance, helper.cardinality);

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
    uint16 _cardinality
  ) internal view returns (uint256) {
    uint32 time = uint32(block.timestamp);
    uint32 targetTimestamp = _target > time ? time : _target;

    Twab memory afterOrAt;
    Twab memory beforeOrAt = _twabs[_twabIndex];

    // If `targetTimestamp` is chronologically at or after the newest TWAB, we can early return
    if (beforeOrAt.timestamp.lte(targetTimestamp, time)) {
      return _currentBalance;
    }

    // Now, set before to the oldest TWAB
    uint16 oldestTwabIndex = wrapCardinality(_twabIndex + 1, _cardinality);
    beforeOrAt = _twabs[oldestTwabIndex];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (beforeOrAt.timestamp == 0) {
      oldestTwabIndex = 0;
      beforeOrAt = _twabs[0];
    }

    // console.log("beforeOrAt.timestamp: ", beforeOrAt.timestamp);
    // console.log("target: ", _target);
    // console.log("twabIndex: ", _twabIndex);
    // console.log("oldestTwabIndex: ", oldestTwabIndex);

    // If `targetTimestamp` is chronologically before the oldest TWAB, we can early return
    if (targetTimestamp.lt(beforeOrAt.timestamp, time)) {
      return 0;
    }

    // Otherwise, we perform the `_binarySearch`
    (beforeOrAt, afterOrAt) = _binarySearch(_twabs, _twabIndex, oldestTwabIndex, _target, _cardinality);

    // Difference in amount / time
    uint224 differenceInAmount = afterOrAt.amount - beforeOrAt.amount;
    uint32 differenceInTime = afterOrAt.timestamp - beforeOrAt.timestamp;

    return differenceInAmount / differenceInTime;
  }

  /// @notice Records a new TWAB.
  /// @param _currentBalance Current `amount`.
  /// @param _nextAvailableTwabIndex Next TWAB index to record to.
  /// @return newTwab New TWAB that was recorded.
  /// @return nextAvailableTwabIndex Next available TWAB index after recording.
  function nextTwab(
    TwabLibrary.Twab memory _currentTwab,
    uint256 _currentBalance,
    uint256 _nextAvailableTwabIndex,
    uint16 _cardinality,
    uint32 currentTimestamp
  ) internal view returns (TwabLibrary.Twab memory newTwab, uint16 nextAvailableTwabIndex) {
    // If a TWAB already exists at this timestamp, then we don't need to update values
    // This is to avoid recording a new TWAB if several transactions happen in the same block
    if (_currentTwab.timestamp == currentTimestamp) {
      return (_currentTwab, nextAvailableTwabIndex);
    }

    // New twab amount = last twab amount (or zero) + (current amount * elapsed seconds)
    newTwab = Twab({
      amount: (uint256(_currentTwab.amount) + (_currentBalance * (currentTimestamp - _currentTwab.timestamp))).toUint224(),
      timestamp: currentTimestamp
    });

    nextAvailableTwabIndex = wrapCardinality(_nextAvailableTwabIndex + 1, _cardinality);
  }
}
