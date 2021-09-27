// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../libraries/TwabLibrary.sol";
import "../libraries/RingBuffer.sol";

/// @title OverflowSafeComparator library to share comparator functions between contracts
/// @author PoolTogether Inc.
contract TwabLibraryExposed {
  uint24 public constant MAX_CARDINALITY = 16777215;

  using TwabLibrary for ObservationLib.Observation[MAX_CARDINALITY];

  TwabLibrary.Account account;

  event Updated(
    TwabLibrary.AccountDetails accountDetails,
    ObservationLib.Observation twab,
    bool isNew
  );

  function increaseBalance(
    uint256 _amount,
    uint32 _ttl,
    uint32 _currentTime
  ) external returns (TwabLibrary.AccountDetails memory accountDetails, ObservationLib.Observation memory twab, bool isNew) {
    (accountDetails, twab, isNew) = TwabLibrary.increaseBalance(account, _amount, _ttl, _currentTime);
    account.details = accountDetails;
    emit Updated(accountDetails, twab, isNew);
  }

  function decreaseBalance(
    uint256 _amount,
    string memory _revertMessage,
    uint32 _ttl,
    uint32 _currentTime
  ) external returns (TwabLibrary.AccountDetails memory accountDetails, ObservationLib.Observation memory twab, bool isNew) {
    (accountDetails, twab, isNew) = TwabLibrary.decreaseBalance(account, _amount, _revertMessage, _ttl, _currentTime);
    account.details = accountDetails;
    emit Updated(accountDetails, twab, isNew);
  }

  function getAverageBalanceBetween(
    uint32 _startTime,
    uint32 _endTime,
    uint32 _currentTime
  ) external view returns (uint256) {
    return TwabLibrary.getAverageBalanceBetween(account.twabs, account.details, _startTime, _endTime, _currentTime);
  }

  function oldestTwab() external view returns (uint24 index, ObservationLib.Observation memory twab) {
    return TwabLibrary.oldestTwab(account.twabs, account.details);
  }

  function newestTwab() external view returns (uint24 index, ObservationLib.Observation memory twab) {
    return TwabLibrary.newestTwab(account.twabs, account.details);
  }

  function getBalanceAt(uint32 _target, uint32 _currentTime) external view returns (uint256) {
    return TwabLibrary.getBalanceAt(account.twabs, account.details, _target, _currentTime);
  }

}
