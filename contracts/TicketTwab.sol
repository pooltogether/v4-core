// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./interfaces/ITicketTwab.sol";
import "./libraries/OverflowSafeComparator.sol";

/// @title Twab contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract TicketTwab is ITicketTwab {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;

  /// @notice Time Weighted Average Balance (TWAB).
  /// @param amount `amount` at `timestamp`.
  /// @param timestamp Recorded `timestamp`.
  struct Twab {
    uint224 amount;
    uint32 timestamp;
  }

  /// @notice Emitted when a new TWAB has been recorded.
  /// @param user Ticket holder address.
  /// @param newTwab Updated TWAB of a ticket holder after a successful TWAB recording.
  event NewUserTwab(
    address indexed user,
    Twab newTwab
  );

  /// @notice TWAB cardinality used to set the size of any twab circular buffer.
  uint32 public constant CARDINALITY = 32;

  /// @notice Record of token holders TWABs for each account.
  mapping (address => Twab[CARDINALITY]) public usersTwabs;

  /// @notice Amount packed with most recent TWAB index.
  /// @param amount Current `amount`.
  /// @param nextTwabIndex Next TWAB index of twab circular buffer.
  struct AmountWithTwabIndex {
    uint240 amount;
    uint16 nextTwabIndex;
  }

  /// @notice Record of token holders balance and most recent TWAB index.
  mapping(address => AmountWithTwabIndex) internal _usersBalanceWithTwabIndex;

  /// @notice Emitted when a new total supply TWAB has been recorded.
  /// @param newTotalSupplyTwab Updated TWAB of tickets total supply after a successful total supply TWAB recording.
  event NewTotalSupplyTwab(
    Twab newTotalSupplyTwab
  );

  /// @notice Record of tickets total supply TWABs.
  Twab[CARDINALITY] public totalSupplyTwabs;

  /// @notice Record of tickets total supply and most recent TWAB index.
  AmountWithTwabIndex internal _totalSupplyWithTwabIndex;

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalance(address _user, uint32 _target) override external view returns (uint256) {
    return _getBalance(_user, _target);
  }

  /// @notice Retrieves `_user` TWAB balances.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] `_user` TWAB balances.
  function getBalances(address _user, uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory balances = new uint256[](length);

    for(uint256 i = 0; i < length; i++){
      balances[i] = _getBalance(_user, _targets[i]);
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

  /// @notice Returns TWAB index.
  /// @dev `twabs` is a circular buffer of `CARDINALITY` size equal to 32. So the array goes from 0 to 31.
  /// @dev In order to navigate the circular buffer, we need to use the modulo operator.
  /// @dev For example, if `_index` is equal to 32, `_index % CARDINALITY` will return 0 and will point to the first element of the array.
  /// @param _index Index used to navigate through `twabs` circular buffer.
  function _moduloCardinality(uint256 _index) internal pure returns (uint16) {
    return uint16(_index % CARDINALITY);
  }

  /// @notice Returns the `mostRecentTwabIndex` of a `_user`.
  /// @param _user Address of the user whose most recent TWAB index is being fetched.
  /// @return uint256 `mostRecentTwabIndex` of `_user`.
  function _mostRecentTwabIndexOfUser(address _user) internal view returns (uint16) {
    return _moduloCardinality(_usersBalanceWithTwabIndex[_user].nextTwabIndex + CARDINALITY - 1);
  }

  /// @notice Returns the `mostRecentTwabIndex` of `totalSupply`.
  /// @return uint256 `mostRecentTwabIndex` of `totalSupply`.
  function _mostRecentTwabIndexOfTotalSupply() internal view returns (uint16) {
    return _moduloCardinality(_totalSupplyWithTwabIndex.nextTwabIndex + CARDINALITY - 1);
  }

  /// @notice Records a new TWAB.
  /// @param _twabs List of TWABs to update.
  /// @param _currentAmount Current `amount`.
  /// @param _nextTwabIndex Next TWAB index to record to.
  /// @return newTwab New TWAB that was recorded.
  /// @return nextAvailableTwabIndex Next available TWAB index after recording.
  function _newTwab(
    Twab[CARDINALITY] storage _twabs,
    uint256 _currentAmount,
    uint16 _nextTwabIndex
  ) internal returns (Twab memory newTwab, uint16 nextAvailableTwabIndex) {
    uint32 currentTimestamp = uint32(block.timestamp);
    Twab memory lastTwab = _twabs[_moduloCardinality(_nextTwabIndex + CARDINALITY - 1)];

    // If a TWAB already exists at this timestamp, then we don't need to update values
    // This is to avoid recording a new TWAB if several transactions happen in the same block
    if (lastTwab.timestamp == currentTimestamp) {
      return (lastTwab, nextAvailableTwabIndex);
    }

    // New twab amount = last twab amount (or zero) + (current amount * elapsed seconds)
    newTwab = Twab({
      amount: lastTwab.amount + (_currentAmount * (currentTimestamp - lastTwab.timestamp)).toUint224(),
      timestamp: currentTimestamp
    });

    _twabs[_nextTwabIndex] = newTwab;

    nextAvailableTwabIndex = _moduloCardinality(_nextTwabIndex + 1);
  }

  /// @notice Records a new TWAB for `_user`.
  /// @param _user Address of the user whose TWAB is being recorded.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newUserTwab(address _user, uint16 _nextTwabIndex) internal returns (uint16) {
    (Twab memory newTwab, uint16 nextAvailableTwabIndex) = _newTwab(usersTwabs[_user], _balanceOf(_user), _nextTwabIndex);

    // We don't record a new TWAB if a TWAB already exists at the same timestamp
    // So we don't emit `NewUserTwab` since no new TWAB has been recorded
    if (nextAvailableTwabIndex != _nextTwabIndex) {
      emit NewUserTwab(_user, newTwab);
    }

    return nextAvailableTwabIndex;
  }

  /// @notice Records a new total supply TWAB.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newTotalSupplyTwab(uint16 _nextTwabIndex) internal returns (uint16) {
    (Twab memory newTwab, uint16 nextAvailableTwabIndex) = _newTwab(totalSupplyTwabs, _ticketTotalSupply(), _nextTwabIndex);

    // We don't record a new TWAB if a TWAB already exists at the same timestamp
    // So we don't emit `NewTotalSupplyTwab` since no new TWAB has been recorded
    if (nextAvailableTwabIndex != _nextTwabIndex) {
      emit NewTotalSupplyTwab(newTwab);
    }

    return nextAvailableTwabIndex;
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
    Twab[CARDINALITY] memory _twabs,
    uint16 _twabIndex,
    uint32 _target
  ) internal view returns (Twab memory beforeOrAt, Twab memory atOrAfter) {
    uint32 time = uint32(block.timestamp);

    uint256 leftSide = _moduloCardinality(_twabIndex + 1); // Oldest TWAB
    uint256 rightSide = leftSide + CARDINALITY - 1; // Newest TWAB
    uint256 currentIndex;

    while (true) {
      currentIndex = (leftSide + rightSide) / 2;
      beforeOrAt = _twabs[_moduloCardinality(currentIndex)];
      uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

      // We've landed on an uninitialized timestamp, keep searching higher (more recently)
      if (beforeOrAtTimestamp == 0) {
          leftSide = currentIndex + 1;
          continue;
      }

      atOrAfter = _twabs[_moduloCardinality(currentIndex + 1)];

      bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, time);

      // Check if we've found the corresponding TWAB
      if (targetAtOrAfter && _target.lt(atOrAfter.timestamp, time)) break;

      // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
      if (!targetAtOrAfter) rightSide = currentIndex - 1;

      // Otherwise, we keep searching higher
      else leftSide = currentIndex + 1;
    }
  }

  /// @notice Retrieves TWAB amount at `_target`.
  /// @param _twabs List of TWABs to search through.
  /// @param _currentAmount Most recent amount recorded.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @param _twabIndex Most recent TWAB index recorded.
  /// @return uint256 TWAB amount at `_target`.
  function _getAmount(
    Twab[CARDINALITY] memory _twabs,
    uint32 _target,
    uint256 _currentAmount,
    uint16 _twabIndex
  ) internal view returns (uint256) {
    uint32 time = uint32(block.timestamp);
    uint32 targetTimestamp = _target > time ? time : _target;

    Twab memory afterOrAt;
    Twab memory beforeOrAt = _twabs[_twabIndex];

    // If `targetTimestamp` is chronologically at or after the newest TWAB, we can early return
    if (beforeOrAt.timestamp.lte(targetTimestamp, time)) {
      return _currentAmount;
    }

    // Now, set before to the oldest TWAB
    beforeOrAt = _twabs[_moduloCardinality(_twabIndex + 1)];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (beforeOrAt.timestamp == 0) beforeOrAt = _twabs[0];

    // If `targetTimestamp` is chronologically before the oldest TWAB, we can early return
    if (targetTimestamp.lt(beforeOrAt.timestamp, time)) {
      return 0;
    }

    // Otherwise, we perform the `_binarySearch`
    (beforeOrAt, afterOrAt) = _binarySearch(_twabs, _twabIndex, _target);

    // Difference in amount / time
    uint224 differenceInAmount = afterOrAt.amount - beforeOrAt.amount;
    uint32 differenceInTime = afterOrAt.timestamp - beforeOrAt.timestamp;

    return differenceInAmount / differenceInTime;
  }

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getBalance(address _user, uint32 _target) internal view returns (uint256) {
    return _getAmount(usersTwabs[_user], _target, _balanceOf(_user), _mostRecentTwabIndexOfUser(_user));
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getTotalSupply(uint32 _target) internal view returns (uint256) {
    return _getAmount(totalSupplyTwabs, _target, _ticketTotalSupply(), _mostRecentTwabIndexOfTotalSupply());
  }

}
