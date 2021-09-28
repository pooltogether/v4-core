// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./ExtendedSafeCast.sol";
import "./OverflowSafeComparator.sol";
import "./RingBuffer.sol";
import "./ObservationLib.sol";

/// @title Time-Weighted Average Balance Library
/// @notice This library allows you to efficiently track a user's historic balance.  You can get a
/// @author PoolTogether Inc.
library TwabLib {
   using OverflowSafeComparator for uint32;
    using ExtendedSafeCast for uint256;

  /// @notice The maximum number of twab entries
  uint24 public constant MAX_CARDINALITY = 16777215; // 2**24

  /// @notice A struct containing details for an Account
  /// @param balance The current balance for an Account
  /// @param nextTwabIndex The next available index to store a new twab
  /// @param cardinality The number of recorded twabs (plus one!)
  struct AccountDetails {
    uint208 balance;
    uint24 nextTwabIndex;
    uint24 cardinality;
  }

  /// @notice Combines account details with their twab history
  /// @param details The account details
  /// @param twabs The history of twabs for this account
  struct Account {
    AccountDetails details;
    ObservationLib.Observation[MAX_CARDINALITY] twabs;
  }

  /// @notice Increases an account's balance and records a new twab.
  /// @param _account The account whose balance will be increased
  /// @param _amount The amount to increase the balance by
  /// @param _ttl The time to live for twabs
  /// @param _currentTime The current time
  /// @return accountDetails The new AccountDetails
  /// @return twab The user's latest TWAB
  /// @return isNew Whether the TWAB is new
  function increaseBalance(
    Account storage _account,
    uint256 _amount,
    uint32 _ttl,
    uint32 _currentTime
  ) internal returns (AccountDetails memory accountDetails, ObservationLib.Observation memory twab, bool isNew) {
    AccountDetails memory _accountDetails = _account.details;
    (accountDetails, twab, isNew) = _nextTwabWithExpiry(_account.twabs, _accountDetails, _ttl, _currentTime);
    accountDetails.balance = (_accountDetails.balance + _amount).toUint208();
  }

  /// @notice Decreases an account's balance and records a new twab.
  /// @param _account The account whose balance will be decreased
  /// @param _amount The amount to decrease the balance by
  /// @param _revertMessage The revert message in the event of insufficient balance
  /// @return accountDetails The new AccountDetails
  /// @return twab The user's latest TWAB
  /// @return isNew Whether the TWAB is new
  function decreaseBalance(
    Account storage _account,
    uint256 _amount,
    string memory _revertMessage,
    uint32 _ttl,
    uint32 _currentTime
  ) internal returns (AccountDetails memory accountDetails, ObservationLib.Observation memory twab, bool isNew) {
    AccountDetails memory _accountDetails = _account.details;
    require(_accountDetails.balance >= _amount, _revertMessage);
    (accountDetails, twab, isNew) = _nextTwabWithExpiry(_account.twabs, _accountDetails, _ttl, _currentTime);
    accountDetails.balance = (_accountDetails.balance - _amount).toUint208();
  }

  /// @notice Calculates the average balance held by a user for a given time frame.
  /// @param _startTime The start time of the time frame.
  /// @param _endTime The end time of the time frame.
  /// @return The average balance that the user held during the time frame.
  function getAverageBalanceBetween(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _startTime,
    uint32 _endTime,
    uint32 _currentTime
  ) internal view returns (uint256) {
    uint32 endTime = _endTime > _currentTime ? _currentTime : _endTime;
    return _getAverageBalanceBetween(_twabs, _accountDetails, _startTime, endTime, _currentTime);
  }

  /// @notice Retrieves the oldest TWAB
  /// @param _twabs The storage array of twabs
  /// @param _accountDetails The TWAB account details
  /// @return index The index of the oldest TWAB in the twabs array
  /// @return twab The oldest TWAB
  function oldestTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails
  ) internal view returns (uint24 index, ObservationLib.Observation memory twab) {
    index = _accountDetails.nextTwabIndex;
    twab = _twabs[_accountDetails.nextTwabIndex];
    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (twab.timestamp == 0) {
      index = 0;
      twab = _twabs[0];
    }
  }

  /// @notice Retrieves the newest TWAB
  /// @param _twabs The storage array of twabs
  /// @param _accountDetails The TWAB account details
  /// @return index The index of the newest TWAB in the twabs array
  /// @return twab The newest TWAB
  function newestTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails
  ) internal view returns (uint24 index, ObservationLib.Observation memory twab) {
    index = uint24(RingBuffer.mostRecentIndex(_accountDetails.nextTwabIndex, _accountDetails.cardinality));
    twab = _twabs[index];
  }

  /// @notice Retrieves amount at `_target` timestamp
  /// @param _twabs List of TWABs to search through.
  /// @param _accountDetails Accounts details
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @return uint256 TWAB amount at `_target`.
  function getBalanceAt(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _target,
    uint32 _currentTime
  ) internal view returns (uint256) {
    uint32 target = _target > _currentTime ? _currentTime : _target;
    return _getBalanceAt(_twabs, _accountDetails, target, _currentTime);
  }

  /// @notice Calculates the average balance held by a user for a given time frame.
  /// @param _startTime The start time of the time frame.
  /// @param _endTime The end time of the time frame.
  /// @return The average balance that the user held during the time frame.
  function _getAverageBalanceBetween(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _startTime,
    uint32 _endTime,
    uint32 _currentTime
  ) private view returns (uint256) {
    (uint24 oldestTwabIndex, ObservationLib.Observation memory oldTwab) = oldestTwab(_twabs, _accountDetails);
    (uint24 newestTwabIndex, ObservationLib.Observation memory newTwab) = newestTwab(_twabs, _accountDetails);

    ObservationLib.Observation memory startTwab = _calculateTwab(
      _twabs, _accountDetails, newTwab, oldTwab, newestTwabIndex, oldestTwabIndex, _startTime, _currentTime
    );

    ObservationLib.Observation memory endTwab = _calculateTwab(
      _twabs, _accountDetails, newTwab, oldTwab, newestTwabIndex, oldestTwabIndex, _endTime, _currentTime
    );

    // Difference in amount / time
    return (endTwab.amount - startTwab.amount) / (endTwab.timestamp - startTwab.timestamp);
  }

  /// @notice Retrieves amount at `_target` timestamp
  /// @param _twabs List of TWABs to search through.
  /// @param _accountDetails Accounts details
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @return uint256 TWAB amount at `_target`.
  function _getBalanceAt(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _target,
    uint32 _currentTime
  ) private view returns (uint256) {
    uint24 newestTwabIndex;
    ObservationLib.Observation memory afterOrAt;
    ObservationLib.Observation memory beforeOrAt;
    (newestTwabIndex, beforeOrAt) = newestTwab(_twabs, _accountDetails);

    // If `_target` is chronologically after the newest TWAB, we can simply return the current balance
    if (beforeOrAt.timestamp.lte(_target, _currentTime)) {
      return _accountDetails.balance;
    }

    uint24 oldestTwabIndex;
    // Now, set before to the oldest TWAB
    (oldestTwabIndex, beforeOrAt) = oldestTwab(_twabs, _accountDetails);

    // If `_target` is chronologically before the oldest TWAB, we can early return
    if (_target.lt(beforeOrAt.timestamp, _currentTime)) {
      return 0;
    }

    // Otherwise, we perform the `binarySearch`
    (beforeOrAt, afterOrAt) = ObservationLib.binarySearch(
      _twabs,
      newestTwabIndex,
      oldestTwabIndex,
      _target,
      _accountDetails.cardinality,
      _currentTime
    );

    // Difference in amount / time
    uint224 differenceInAmount = afterOrAt.amount - beforeOrAt.amount;
    uint32 differenceInTime = afterOrAt.timestamp - beforeOrAt.timestamp;

    return differenceInAmount / differenceInTime;
  }

  /// @notice Calculates the TWAB for a given timestamp.  It interpolates as necessary.
  /// @param _twabs The TWAB history
  function _calculateTwab(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    ObservationLib.Observation memory _newestTwab,
    ObservationLib.Observation memory _oldestTwab,
    uint24 _newestTwabIndex,
    uint24 _oldestTwabIndex,
    uint32 targetTimestamp,
    uint32 _time
  ) private view returns (ObservationLib.Observation memory) {
    // If `targetTimestamp` is chronologically after the newest TWAB, we extrapolate a new one
    if (_newestTwab.timestamp.lt(targetTimestamp, _time)) {
      return ObservationLib.Observation({
        amount: _newestTwab.amount + _accountDetails.balance*(targetTimestamp - _newestTwab.timestamp),
        timestamp: targetTimestamp
      });
    }

    if (_newestTwab.timestamp == targetTimestamp) {
      return _newestTwab;
    }

    if (_oldestTwab.timestamp == targetTimestamp) {
      return _oldestTwab;
    }

    // If `targetTimestamp` is chronologically before the oldest TWAB, we create a zero twab
    if (targetTimestamp.lt(_oldestTwab.timestamp, _time)) {
      return ObservationLib.Observation({
        amount: 0,
        timestamp: targetTimestamp
      });
    }

    // Otherwise, both timestamps must be surrounded by twabs.
    (
      ObservationLib.Observation memory beforeOrAtStart,
      ObservationLib.Observation memory afterOrAtStart
    ) = ObservationLib.binarySearch(_twabs, _newestTwabIndex, _oldestTwabIndex, targetTimestamp, _accountDetails.cardinality, _time);

    uint224 heldBalance = (afterOrAtStart.amount - beforeOrAtStart.amount) / (afterOrAtStart.timestamp - beforeOrAtStart.timestamp);
    uint224 amount = beforeOrAtStart.amount + heldBalance * (targetTimestamp - beforeOrAtStart.timestamp);

    return ObservationLib.Observation({
      amount: amount,
      timestamp: targetTimestamp
    });
  }

  /// @notice Records a new TWAB.
  /// @param _currentBalance Current `amount`.
  /// @return New TWAB that was recorded.
  function _nextTwab(
    ObservationLib.Observation memory _currentTwab,
    uint256 _currentBalance,
    uint32 _time
  ) private pure returns (ObservationLib.Observation memory) {
    // New twab amount = last twab amount (or zero) + (current amount * elapsed seconds)
    return ObservationLib.Observation({
      amount: (uint256(_currentTwab.amount) + (_currentBalance * (_time.checkedSub(_currentTwab.timestamp, _time)))).toUint208(),
      timestamp: _time
    });
  }

  function _calculateNextWithExpiry(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _ttl,
    uint32 _time
  ) private view returns (AccountDetails memory) {
    uint24 cardinality = _accountDetails.cardinality > 0 ? _accountDetails.cardinality : 1;
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

    ObservationLib.Observation memory secondOldestTwab;
    // if there are two or more records (cardinality is always one greater than # of records)
    if (cardinality > 2) {
      // get the second oldest twab
      (uint24 oldestTwabIndex,) = oldestTwab(_twabs, _accountDetails);
      uint24 secondOldestTwabIndex = uint24(RingBuffer.nextIndex(oldestTwabIndex, cardinality));
      secondOldestTwab = _twabs[secondOldestTwabIndex];
    }

    uint24 nextCardinality = cardinality;
    if (secondOldestTwab.timestamp == 0 || _time.checkedSub(secondOldestTwab.timestamp, _time) < _ttl) {
      nextCardinality = cardinality < MAX_CARDINALITY ? cardinality + 1 : MAX_CARDINALITY;
    }

    uint24 nextAvailableTwabIndex = uint24(RingBuffer.nextIndex(_accountDetails.nextTwabIndex, nextCardinality));

    return AccountDetails({
      balance: _accountDetails.balance,
      nextTwabIndex: nextAvailableTwabIndex,
      cardinality: nextCardinality
    });
  }

  /// @notice Sets a new TWAB Observation at the next available index and returns the new account details.
  /// @param _twabs The twabs array to insert into
  /// @param _accountDetails The current account details
  /// @param _ttl The time to live for twabs
  /// @param _time The current time
  /// @return accountDetails The new account details
  /// @return twab The newest twab (may or may not be brand-new)
  /// @return isNew Whether the newest twab was created by this call
  function _nextTwabWithExpiry(
    ObservationLib.Observation[MAX_CARDINALITY] storage _twabs,
    AccountDetails memory _accountDetails,
    uint32 _ttl,
    uint32 _time
  ) private returns (AccountDetails memory accountDetails, ObservationLib.Observation memory twab, bool isNew) {
    (, ObservationLib.Observation memory _newestTwab) = newestTwab(_twabs, _accountDetails);
    require(_time >= _newestTwab.timestamp, "TwabLib/twab-time-monotonic");

    // if we're in the same block, return
    if (_newestTwab.timestamp == _time) {
      return (_accountDetails, _newestTwab, false);
    }

    AccountDetails memory nextAccountDetails = _calculateNextWithExpiry(_twabs, _accountDetails, _ttl, _time);

    ObservationLib.Observation memory newTwab = _nextTwab(
      _newestTwab,
      _accountDetails.balance,
      _time
    );

    _twabs[_accountDetails.nextTwabIndex] = newTwab;

    return (nextAccountDetails, newTwab, true);
  }
}