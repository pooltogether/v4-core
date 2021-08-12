// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./interfaces/ITicketTwab.sol";
import "./libraries/TwabLibrary.sol";
import "./libraries/OverflowSafeComparator.sol";

/// @title Twab contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract TicketTwab is ITicketTwab {
  uint16 public constant CARDINALITY = 4;

  using SafeERC20Upgradeable for IERC20Upgradeable;
  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;
  using TwabLibrary for TwabLibrary.Twab[CARDINALITY];

  /// @notice Emitted when a new TWAB has been recorded.
  /// @param user Ticket holder address.
  /// @param newTwab Updated TWAB of a ticket holder after a successful TWAB recording.
  event NewUserTwab(
    address indexed user,
    TwabLibrary.Twab newTwab
  );

  /// @notice Record of token holders TWABs for each account.
  mapping (address => TwabLibrary.Twab[CARDINALITY]) public usersTwabs;

  /// @notice Amount packed with most recent TWAB index.
  /// @param amount Current `amount`.
  /// @param nextTwabIndex Next TWAB index of twab circular buffer.
  struct AmountWithTwabIndex {
    uint240 amount;
    uint16 nextTwabIndex;
    // uint16 cardinality;
  }

  /// @notice Record of token holders balance and most recent TWAB index.
  mapping(address => AmountWithTwabIndex) internal _usersBalanceWithTwabIndex;

  /// @notice Emitted when a new total supply TWAB has been recorded.
  /// @param newTotalSupplyTwab Updated TWAB of tickets total supply after a successful total supply TWAB recording.
  event NewTotalSupplyTwab(
    TwabLibrary.Twab newTotalSupplyTwab
  );

  /// @notice Record of tickets total supply TWABs.
  TwabLibrary.Twab[CARDINALITY] public totalSupplyTwabs;

  /// @notice Record of tickets total supply and most recent TWAB index.
  AmountWithTwabIndex internal _totalSupplyWithTwabIndex;

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalance(address _user, uint32 _target) override external view returns (uint256) {
    return _getBalance(_user, _target);
  }

  function getAverageBalance(address _user, uint32 _startTime, uint32 _endTime) external view returns (uint256) {
    return _getAverageBalance(_user, _startTime, _endTime);
  }

  function _getAverageBalance(address _user, uint32 _startTime, uint32 _endTime) internal view returns (uint256) {
    return TwabLibrary.getAverageBalanceBetween(
      usersTwabs[_user],
      _balanceOf(_user).toUint224(),
      _mostRecentTwabIndexOfUser(_user),
      _startTime,
      _endTime,
      CARDINALITY
    );
  }

  /// @notice Retrieves `_user` TWAB balances.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] `_user` TWAB balances.
  function getBalances(address _user, uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory balances = new uint256[](length);

    TwabLibrary.Twab[CARDINALITY] storage twabs = usersTwabs[_user];
    uint224 currentBalance = _balanceOf(_user).toUint224();
    uint16 twabIndex = _mostRecentTwabIndexOfUser(_user);

    for(uint256 i = 0; i < length; i++){
      balances[i] = twabs.getBalanceAt(_targets[i], currentBalance, twabIndex, CARDINALITY);
    }

    return balances;
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getTotalSupply(uint32 _target) override external view returns (uint256) {
    return _getTotalSupply(_target);
  }

  /// @notice Retrieves ticket TWAB `totalSupplies`.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] ticket TWAB `totalSupplies`.
  function getTotalSupplies(uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory totalSupplies = new uint256[](length);

    for(uint256 i = 0; i < length; i++){
      totalSupplies[i] = _getTotalSupply(_targets[i]);
    }

    return totalSupplies;
  }

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint256 `_user` ticket token balance.
  function _balanceOf(address _user) internal view returns (uint256) {
    return _usersBalanceWithTwabIndex[_user].amount;
  }

  /// @notice Returns the ERC20 ticket token total supply.
  /// @return uint256 Total supply of the ERC20 ticket token.
  function _ticketTotalSupply() internal view returns (uint256) {
    return _totalSupplyWithTwabIndex.amount;
  }

  /// @notice Returns the `mostRecentTwabIndex` of a `_user`.
  /// @param _user Address of the user whose most recent TWAB index is being fetched.
  /// @return uint256 `mostRecentTwabIndex` of `_user`.
  function _mostRecentTwabIndexOfUser(address _user) internal view returns (uint16) {
    return TwabLibrary.mostRecentIndex(_usersBalanceWithTwabIndex[_user].nextTwabIndex, CARDINALITY);
  }

  /// @notice Returns the `mostRecentTwabIndex` of `totalSupply`.
  /// @return uint256 `mostRecentTwabIndex` of `totalSupply`.
  function _mostRecentTwabIndexOfTotalSupply() internal view returns (uint16) {
    return TwabLibrary.mostRecentIndex(_totalSupplyWithTwabIndex.nextTwabIndex, CARDINALITY);
  }

  /// @notice Records a new TWAB for `_user`.
  /// @param _user Address of the user whose TWAB is being recorded.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newUserTwab(address _user, uint16 _nextTwabIndex) internal returns (uint16) {
    uint32 currentTimestamp = uint32(block.timestamp);
    TwabLibrary.Twab memory lastTwab = usersTwabs[_user][TwabLibrary.mostRecentIndex(_nextTwabIndex, CARDINALITY)];
    (TwabLibrary.Twab memory newTwab, uint16 nextAvailableTwabIndex) = TwabLibrary.nextTwab(
      lastTwab,
      _balanceOf(_user),
      _nextTwabIndex,
      CARDINALITY,
      currentTimestamp
    );

    // We don't record a new TWAB if a TWAB already exists at the same timestamp
    // So we don't emit `NewUserTwab` since no new TWAB has been recorded
    if (nextAvailableTwabIndex != _nextTwabIndex) {
      usersTwabs[_user][_nextTwabIndex] = newTwab;
      emit NewUserTwab(_user, newTwab);
    }

    return nextAvailableTwabIndex;
  }

  /// @notice Records a new total supply TWAB.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newTotalSupplyTwab(uint16 _nextTwabIndex) internal returns (uint16) {
    uint32 currentTimestamp = uint32(block.timestamp);
    TwabLibrary.Twab memory lastTwab = totalSupplyTwabs[TwabLibrary.mostRecentIndex(_nextTwabIndex, CARDINALITY)];
    (TwabLibrary.Twab memory newTwab, uint16 nextAvailableTwabIndex) = TwabLibrary.nextTwab(
      lastTwab,
      _ticketTotalSupply(),
      _nextTwabIndex,
      CARDINALITY,
      currentTimestamp
    );

    // We don't record a new TWAB if a TWAB already exists at the same timestamp
    // So we don't emit `NewTotalSupplyTwab` since no new TWAB has been recorded
    if (nextAvailableTwabIndex != _nextTwabIndex) {
      totalSupplyTwabs[_nextTwabIndex] = newTwab;
      emit NewTotalSupplyTwab(newTwab);
    }

    return nextAvailableTwabIndex;
  }

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getBalance(address _user, uint32 _target) internal view returns (uint256) {
    return usersTwabs[_user].getBalanceAt(_target, _balanceOf(_user), _mostRecentTwabIndexOfUser(_user), CARDINALITY);
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getTotalSupply(uint32 _target) internal view returns (uint256) {
    return totalSupplyTwabs.getBalanceAt(_target, _ticketTotalSupply(), _mostRecentTwabIndexOfTotalSupply(), CARDINALITY);
  }

}
