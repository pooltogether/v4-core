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

  /// @notice Time Weighted Average Balance (TWAB) of ticket holders.
  /// @param balance User balance at `timestamp`.
  /// @param timestamp Recorded timestamp.
  struct Twab {
    uint224 balance;
    uint32 timestamp;
  }

  /// @notice Emitted when a new TWAB has been recorded.
  /// @param user Ticket holder address.
  /// @param newTwab Updated TWAB of a ticket holder after a successful TWAB recording.
  event NewTwab(
    address indexed user,
    Twab newTwab
  );

  /// @notice TWAB cardinality used to set the size of `twabs` circular buffer.
  uint32 public constant CARDINALITY = 32;

  /// @notice Record of token holders TWABs for each account.
  mapping (address => Twab[CARDINALITY]) public twabs;

  /// @notice Balance of a ticket holder packed with most recent TWAB index.
  /// @param balance Current user balance.
  /// @param nextTwabIndex Next TWAB index of user.
  struct BalanceWithTwabIndex {
    uint240 balance;
    uint16 nextTwabIndex;
  }

  /// @notice Record of token holders balance and most recent TWAB index.
  mapping(address => BalanceWithTwabIndex) internal _balancesWithTwabIndex;

  /// @notice Time Weighted Average Balance (TWAB) of tickets total supply.
  /// @param totalSupply Total supply at `timestamp`.
  /// @param timestamp Recorded timestamp.
  struct TotalSupplyTwab {
    uint224 totalSupply;
    uint32 timestamp;
  }

  /// @notice Emitted when a new total supply TWAB has been recorded.
  /// @param newTotalSupplyTwab Updated TWAB of tickets total supply after a successful total supply TWAB recording.
  event NewTotalSupplyTwab(
    TotalSupplyTwab newTotalSupplyTwab
  );

  /// @notice Record of tickets total supply TWABs.
  TotalSupplyTwab[CARDINALITY] public totalSupplytwab;

  /// @notice Total supply of tickets packed with most recent TWAB index.
  /// @param totalSupply Current tickets total supply.
  /// @param nextTwabIndex Next TWAB index of totalSupplytwab.
  struct TotalSupplyWithTwabIndex {
    uint240 totalSupply;
    uint16 nextTwabIndex;
  }

  /// @notice Record of tickets total supply and most recent TWAB index.
  TotalSupplyWithTwabIndex internal _totalSupplyWithTwabIndex;

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalance(address _user, uint32 _target) override external view returns (uint256) {
    uint16 index = _mostRecentTwabIndexOfUser(_user);
    return _getBalance(_user, _target, index);
  }

  /// @notice Retrieves `_user` TWAB balances.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] `_user` TWAB balances.
  function getBalances(address _user, uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory balances = new uint256[](length);

    uint16 index = _mostRecentTwabIndexOfUser(_user);

    for(uint256 i = 0; i < length; i++){
      balances[i] = _getBalance(_user, _targets[i], index);
    }

    return balances;
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getTotalSupply(uint32 _target) override external view returns (uint256) {
    uint16 index = _mostRecentTwabIndexOfTotalSupply();
    return _getTotalSupply(_target, index);
  }

  /// @notice Retrieves ticket TWAB `totalSupplies`.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] ticket TWAB `totalSupplies`.
  function getTotalSupplies(uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory totalSupplies = new uint256[](length);

    uint16 index = _mostRecentTwabIndexOfTotalSupply();

    for(uint256 i = 0; i < length; i++){
      totalSupplies[i] = _getTotalSupply(_targets[i], index);
    }

    return totalSupplies;
  }

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint240 `_user` ticket token balance.
  function _balanceOf(address _user) internal view returns (uint256) {
    return _balancesWithTwabIndex[_user].balance;
  }

  /// @notice Returns the ERC20 ticket token total supply.
  /// @return uint256 Total supply of the ERC20 ticket token.
  function _ticketTotalSupply() internal view returns (uint256) {
    return _totalSupplyWithTwabIndex.totalSupply;
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
    return _moduloCardinality(_balancesWithTwabIndex[_user].nextTwabIndex + CARDINALITY - 1);
  }

  /// @notice Returns the `mostRecentTwabIndex` of `totalSupply`.
  /// @return uint256 `mostRecentTwabIndex` of `totalSupply`.
  function _mostRecentTwabIndexOfTotalSupply() internal view returns (uint16) {
    return _moduloCardinality(_totalSupplyWithTwabIndex.nextTwabIndex + CARDINALITY - 1);
  }

  /// @notice Records a new TWAB for `_user`.
  /// @param _user Address of the user whose TWAB is being recorded.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newTwab(address _user, uint16 _nextTwabIndex) internal returns (uint16) {
    uint32 currentTimestamp = uint32(block.timestamp);
    Twab memory lastTwab = twabs[_user][_moduloCardinality(_nextTwabIndex + CARDINALITY - 1)];

    // If a TWAB already exists at this timestamp, then we don't need to update values
    // This is to avoid recording a new TWAB if several transactions happen in the same block
    if (lastTwab.timestamp == currentTimestamp) {
      return _nextTwabIndex;
    }

    // New twab = last twab balance (or zero) + (previous user balance * elapsed seconds)
    uint32 elapsedSeconds = currentTimestamp - lastTwab.timestamp;
    uint224 newTwabBalance = (lastTwab.balance + (_balanceOf(_user) * elapsedSeconds)).toUint224();

    // Record new TWAB
    Twab memory newTwab = Twab ({
      balance: newTwabBalance,
      timestamp: currentTimestamp
    });

    twabs[_user][_nextTwabIndex] = newTwab;

    emit NewTwab(_user, newTwab);

    return _moduloCardinality(_nextTwabIndex + 1);
  }

  /// @notice Records a new total supply TWAB.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newTotalSupplyTwab(uint16 _nextTwabIndex) internal returns (uint16) {
    uint32 currentTimestamp = uint32(block.timestamp);
    TotalSupplyTwab memory lastTwab = totalSupplytwab[_moduloCardinality(_nextTwabIndex + CARDINALITY - 1)];

    // If a TWAB already exists at this timestamp, then we don't need to update values
    // This is to avoid recording a new TWAB if several transactions happen in the same block
    if (lastTwab.timestamp == currentTimestamp) {
      return _nextTwabIndex;
    }

    // New twab = last twab total supply (or zero) + (previous total supply * elapsed seconds)
    uint32 elapsedSeconds = currentTimestamp - lastTwab.timestamp;
    uint224 newTwabTotalSupply = (lastTwab.totalSupply + (_ticketTotalSupply() * elapsedSeconds)).toUint224();

    // Record new TWAB
    TotalSupplyTwab memory newTwab = TotalSupplyTwab ({
      totalSupply: newTwabTotalSupply,
      timestamp: currentTimestamp
    });

    totalSupplytwab[_nextTwabIndex] = newTwab;

    emit NewTotalSupplyTwab(newTwab);

    return _moduloCardinality(_nextTwabIndex + 1);
  }

  /// @notice Fetches user TWABs `beforeOrAt` and `atOrAfter` a `_target`, eg: where [`beforeOrAt`, `atOrAfter`] is satisfied.
  /// The result may be the same TWAB, or adjacent TWABs.
  /// @dev The answer must be contained in the array, used when the target is located within the stored TWAB.
  /// boundaries: older than the most recent TWAB and younger, or the same age as, the oldest TWAB.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @return beforeOrAt TWAB recorded before, or at, the target.
  /// @return atOrAfter TWAB recorded at, or after, the target.
  function _binarySearch(
      address _user,
      uint32 _target
  ) internal view returns (Twab memory beforeOrAt, Twab memory atOrAfter) {
    uint32 time = uint32(block.timestamp);
    uint16 twabIndex = _mostRecentTwabIndexOfUser(_user);

    uint256 leftSide = _moduloCardinality(twabIndex + 1); // Oldest TWAB
    uint256 rightSide = leftSide + CARDINALITY - 1; // Newest TWAB
    uint256 currentIndex;

    while (true) {
      currentIndex = (leftSide + rightSide) / 2;
      beforeOrAt = twabs[_user][_moduloCardinality(currentIndex)];
      uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

      // We've landed on an uninitialized timestamp, keep searching higher (more recently)
      if (beforeOrAtTimestamp == 0) {
          leftSide = currentIndex + 1;
          continue;
      }

      atOrAfter = twabs[_user][_moduloCardinality(currentIndex + 1)];

      bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, time);

      // Check if we've found the corresponding TWAB
      if (targetAtOrAfter && _target.lt(atOrAfter.timestamp, time)) break;

      // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
      if (!targetAtOrAfter) rightSide = currentIndex - 1;

      // Otherwise, we keep searching higher
      else leftSide = currentIndex + 1;
    }
  }

  /// @notice Retrieves `_user` TWAB balance at `_target`.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @param _twabIndex The most recent TWAB index of `_user`.
  /// @return uint256 `_user` TWAB balance at `_target`.
  function _getBalance(address _user, uint32 _target, uint16 _twabIndex) internal view returns (uint256) {
    uint32 time = uint32(block.timestamp);
    uint32 targetTimestamp = _target > time ? time : _target;

    Twab memory afterOrAt;
    Twab memory beforeOrAt = twabs[_user][_twabIndex];

    // If `targetTimestamp` is chronologically at or after the newest TWAB, we can early return
    if (beforeOrAt.timestamp.lte(targetTimestamp, time)) {
      return _balanceOf(_user);
    }

    // Now, set before to the oldest TWAB
    beforeOrAt = twabs[_user][_moduloCardinality(_twabIndex + 1)];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (beforeOrAt.timestamp == 0) beforeOrAt = twabs[_user][0];

    // If `targetTimestamp` is chronologically before the oldest TWAB, we can early return
    if (targetTimestamp.lt(beforeOrAt.timestamp, time)) {
      return 0;
    }

    // Otherwise, we perform the `_binarySearch`
    (beforeOrAt, afterOrAt) = _binarySearch(_user, _target);

    // Difference in balance / time
    uint224 differenceInBalance = afterOrAt.balance - beforeOrAt.balance;
    uint32 differenceInTime = afterOrAt.timestamp - beforeOrAt.timestamp;

    return differenceInBalance / differenceInTime;
  }

  /// @notice Fetches totalSupply TWABs `beforeOrAt` and `atOrAfter` a `_target`, eg: where [`beforeOrAt`, `atOrAfter`] is satisfied.
  /// The result may be the same TWAB, or adjacent TWABs.
  /// @dev The answer must be contained in the array, used when the target is located within the stored TWAB.
  /// boundaries: older than the most recent TWAB and younger, or the same age as, the oldest TWAB.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @return beforeOrAt TWAB recorded before, or at, the target.
  /// @return atOrAfter TWAB recorded at, or after, the target.
  function _binarySearchTotalSupply(
      uint32 _target
  ) internal view returns (TotalSupplyTwab memory beforeOrAt, TotalSupplyTwab memory atOrAfter) {
    uint32 time = uint32(block.timestamp);
    uint16 twabIndex = _mostRecentTwabIndexOfTotalSupply();

    uint256 leftSide = _moduloCardinality(twabIndex + 1); // Oldest TWAB
    uint256 rightSide = leftSide + CARDINALITY - 1; // Newest TWAB
    uint256 currentIndex;

    while (true) {
      currentIndex = (leftSide + rightSide) / 2;
      beforeOrAt = totalSupplytwab[_moduloCardinality(currentIndex)];
      uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

      // We've landed on an uninitialized timestamp, keep searching higher (more recently)
      if (beforeOrAtTimestamp == 0) {
          leftSide = currentIndex + 1;
          continue;
      }

      atOrAfter = totalSupplytwab[_moduloCardinality(currentIndex + 1)];

      bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, time);

      // Check if we've found the corresponding TWAB
      if (targetAtOrAfter && _target.lt(atOrAfter.timestamp, time)) break;

      // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
      if (!targetAtOrAfter) rightSide = currentIndex - 1;

      // Otherwise, we keep searching higher
      else leftSide = currentIndex + 1;
    }
  }

  /// @notice Retrieves ticket TWAB `totalSupply` at `_target`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @param _twabIndex The most recent TWAB index of `totalSupply`.
  /// @return uint256 ticket TWAB `totalSupply` at `_target`.
  function _getTotalSupply(uint32 _target, uint16 _twabIndex) internal view returns (uint256) {
    uint32 time = uint32(block.timestamp);
    uint32 targetTimestamp = _target > time ? time : _target;

    TotalSupplyTwab memory afterOrAt;
    TotalSupplyTwab memory beforeOrAt = totalSupplytwab[_twabIndex];

    // If `targetTimestamp` is chronologically at or after the newest TWAB, we can early return
    if (beforeOrAt.timestamp.lte(targetTimestamp, time)) {
      return _ticketTotalSupply();
    }

    // Now, set before to the oldest TWAB
    beforeOrAt = totalSupplytwab[_moduloCardinality(_twabIndex + 1)];

    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (beforeOrAt.timestamp == 0) beforeOrAt = totalSupplytwab[0];

    // If `targetTimestamp` is chronologically before the oldest TWAB, we can early return
    if (targetTimestamp.lt(beforeOrAt.timestamp, time)) {
      return 0;
    }

    // Otherwise, we perform the `_binarySearchTotalSupply`
    (beforeOrAt, afterOrAt) = _binarySearchTotalSupply(_target);

    // Difference in totalSupply / time
    uint224 differenceInBalance = afterOrAt.totalSupply - beforeOrAt.totalSupply;
    uint32 differenceInTime = afterOrAt.timestamp - beforeOrAt.timestamp;

    return differenceInBalance / differenceInTime;
  }

}
