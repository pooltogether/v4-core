// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./OverflowSafeComparator.sol";
import "./RingBuffer.sol";

/// @title Time-Weighted Average Balance Library
/// @notice This library allows you to efficiently track a user's historic balance.  You can get a
/// @author PoolTogether Inc.
library ObservationLib {
  using OverflowSafeComparator for uint32;
  using SafeCast for uint256;

  /// @notice The maximum number of twab entries
  uint16 public constant MAX_CARDINALITY = 65535;

  /// @notice Time Weighted Average Balance (TWAB).
  /// @param amount `amount` at `timestamp`.
  /// @param timestamp Recorded `timestamp`.
  struct Observation {
    uint224 amount;
    uint32 timestamp;
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
    Observation[MAX_CARDINALITY] storage _twabs,
    uint16 _twabIndex,
    uint16 _oldestObservationIndex,
    uint32 _target,
    uint16 _cardinality,
    uint32 _time
  ) internal view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
    uint256 leftSide = _oldestObservationIndex; // Oldest TWAB
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

}
