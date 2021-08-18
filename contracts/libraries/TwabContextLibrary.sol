// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "hardhat/console.sol";

import "./TwabLibrary.sol";
import "./OverflowSafeComparator.sol";

/// @title OverflowSafeComparator library to share comparator functions between contracts
/// @author PoolTogether Inc.
library TwabContextLibrary {
  /// @notice The maximum number of twab entries
  uint16 public constant MAX_CARDINALITY = 65535;

  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;
  using TwabLibrary for TwabLibrary.Twab[MAX_CARDINALITY];

  struct Context {
    uint224 amount;
    uint16 nextTwabIndex;
    uint16 cardinality;
  }

  struct TwabContext {
    Context context;
    TwabLibrary.Twab[MAX_CARDINALITY] twabs;
  }

  function _minCardinality(uint16 cardinality) internal pure returns (uint16) {
    return cardinality > 0 ? cardinality : 1;
  }

  /// @notice Retrieves TWAB balance.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalanceAt(TwabContext storage twabContext, uint32 _target, uint32 _time) internal view returns (uint256) {
    Context memory context = twabContext.context;
    uint16 cardinality = _minCardinality(context.cardinality);
    uint16 recentIndex = TwabLibrary.mostRecentIndex(context.nextTwabIndex, cardinality);
    // console.log("getBalanceAt _target: %s, _time: %s ", _target, _time);
    return twabContext.twabs.getBalanceAt(_target, context.amount, recentIndex, cardinality, _time);
  }

  function getAverageBalanceBetween(
    TwabContext storage twabContext,
    uint32 _startTime,
    uint32 _endTime,
    uint32 _time
  ) internal view returns (uint256) {
    Context memory context = twabContext.context;
    uint16 card = _minCardinality(context.cardinality);
    uint16 recentIndex = TwabLibrary.mostRecentIndex(context.nextTwabIndex, card);
    // console.log("getAverageBalanceBetween: amount: %s, index: %s, card: %s", context.amount, recentIndex, card);
    // console.log("getAverageBalanceBetween: startTime: %s, endTime: %s, time: %s", _startTime, _endTime, _time);
    return twabContext.twabs.getAverageBalanceBetween(
      context.amount,
      recentIndex,
      _startTime,
      _endTime,
      card,
      _time
    );
  }

  function increaseBalance(
    TwabContext storage twabContext,
    uint256 _amount,
    uint32 _time,
    uint32 _expiry
  ) internal returns (TwabLibrary.Twab memory twab, bool isNew) {
    Context memory context = twabContext.context;
    uint224 newBalance = (context.amount + _amount).toUint224();
    (context, twab, isNew) = _update(context, twabContext.twabs, newBalance, _time, _expiry);
    twabContext.context = context;
  }

  function decreaseBalance(
    TwabContext storage twabContext,
    uint256 _amount,
    string memory _message,
    uint32 _time,
    uint32 _expiry
  ) internal returns (TwabLibrary.Twab memory twab, bool isNew) {
    Context memory context = twabContext.context;
    require(context.amount >= _amount, _message);
    uint224 newBalance = (context.amount - _amount).toUint224();
    (context, twab, isNew) = _update(context, twabContext.twabs, newBalance, _time, _expiry);
    twabContext.context = context;
  }

  function _update(
    Context memory context,
    TwabLibrary.Twab[MAX_CARDINALITY] storage twabs,
    uint224 _newBalance,
    uint32 _time,
    uint32 _expiry
  ) private returns (
    Context memory newContext,
    TwabLibrary.Twab memory twab,
    bool isNew
  ) {
    uint16 nextTwabIndex;
    uint16 cardinality;

    (nextTwabIndex, cardinality, twab, isNew) = twabs.nextTwabWithExpiry(
      context.amount,
      _newBalance,
      context.nextTwabIndex,
      context.cardinality,
      _time,
      _expiry
    );

    newContext = Context({
      amount: _newBalance,
      nextTwabIndex: nextTwabIndex,
      cardinality: cardinality
    });
  }

}
