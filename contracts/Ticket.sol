// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "hardhat/console.sol";

import "./interfaces/IClaimable.sol";
import "./interfaces/IClaimer.sol";
import "./interfaces/ITicket.sol";
import "./libraries/Math.sol";

/// @title Ticket contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract Ticket is ITicket, IClaimer, ERC20PermitUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using Math for uint32;
  using SafeCastUpgradeable for uint256;
  using SafeMathUpgradeable for uint256;

  /// @notice Emitted when ticket is initialized.
  /// @param name Ticket name (eg: PoolTogether Dai Ticket (Compound)).
  /// @param symbol Ticket symbol (eg: PcDAI).
  /// @param decimals Ticket decimals.
  event TicketInitialized(
    string name,
    string symbol,
    uint8 decimals
  );

  /// @notice Time Weighted Average Balance (TWAB) of ticket holders.
  /// @param balance User balance at `timestamp`.
  /// @param timestamp Recorded timestamp.
  struct Twab {
    uint224 balance;
    uint32 timestamp;
  }

  /// @notice Emitted when ticket is claimed.
  /// @param user Ticket holder address.
  /// @param newTwab Updated TWAB of a ticket holder after a successful transfer.
  event NewTwab(
    address indexed user,
    Twab newTwab
  );

  /// @notice TWAB cardinality used to set the size of `twabs` circular buffer.
  uint32 public constant CARDINALITY = 32;

  /// @notice Record of token holders TWABs for each account.
  mapping (address => Twab[CARDINALITY]) public twabs;

  /// @notice Most recent TWAB index of a ticket holder.
  mapping (address => uint256) internal mostRecentTwabIndex;

  /// @notice ERC20 ticket token decimals.
  uint8 private _decimals;

  /// @notice Initializes Ticket with passed parameters.
  /// @param _name ERC20 ticket token name.
  /// @param _symbol ERC20 ticket token symbol.
  /// @param decimals_ ERC20 ticket token decimals.
  function initialize (
    string calldata _name,
    string calldata _symbol,
    uint8 decimals_
  ) public initializer {
    __ERC20_init(_name, _symbol);
    __ERC20Permit_init("PoolTogether Ticket");

    require(decimals_ > 0, "Ticket/decimals-gt-zero");
    _decimals = decimals_;

    __Ownable_init();

    emit TicketInitialized(_name, _symbol, decimals_);
  }

  /// @notice Returns the ERC20 ticket token decimals.
  /// @dev This value should be equal to the decimals of the token used to deposit into the pool.
  /// @return uint8 decimals.
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  /// @notice Returns TWAB index.
  /// @dev `twabs` is a circular buffer of `CARDINALITY` size equal to 32. So the array goes from 0 to 31.
  /// @dev In order to navigate the circular buffer, we need to use the modulo operator.
  /// @dev For example, if `_index` is equal to 32, `_index % CARDINALITY` will return 0 and will point to the first element of the array.
  /// @param _index Index used to navigate through `twabs` circular buffer.
  function _getTwabIndex(uint256 _index) internal pure returns (uint256) {
    return _index % CARDINALITY;
  }


  /// @notice Returns the `mostRecentTwabIndex` of a `_user`.
  /// @param _user Address of the user whose most recent TWAB index is being fetched.
  /// @return uint256 `mostRecentTwabIndex` of `_user`.
  function _mostRecentTwabIndexOfUser(address _user) internal view returns (uint256) {
    uint32 cardinality = CARDINALITY;
    return _getTwabIndex(mostRecentTwabIndex[_user] + cardinality - 1);
  }

  /// @notice Fetches the TWABs `beforeOrAt` and `atOrAfter` a `_target`, eg: where [`beforeOrAt`, `atOrAfter`] is satisfied.
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
      uint256 twabIndex = _mostRecentTwabIndexOfUser(_user);

      uint32 cardinality = CARDINALITY;

      uint256 leftSide = _getTwabIndex(twabIndex + 1); // Oldest TWAB
      uint256 rightSide = leftSide + cardinality - 1; // Newest TWAB
      uint256 currentIndex;

      while (true) {
          currentIndex = (leftSide + rightSide) / 2;
          beforeOrAt = twabs[_user][_getTwabIndex(currentIndex)];
          uint32 beforeOrAtTimestamp = beforeOrAt.timestamp;

          // We've landed on an uninitialized timestamp, keep searching higher (more recently)
          if (beforeOrAtTimestamp == 0) {
              leftSide = currentIndex + 1;
              continue;
          }

          atOrAfter = twabs[_user][_getTwabIndex(currentIndex + 1)];

          bool targetAtOrAfter = beforeOrAtTimestamp.lte(_target, time);

          // Check if we've found the corresponding TWAB
          if (targetAtOrAfter && _target.lt(atOrAfter.timestamp, time)) break;

          // If `beforeOrAtTimestamp` is greater than `_target`, then we keep searching lower
          if (!targetAtOrAfter) rightSide = currentIndex - 1;

          // Otherwise, we keep searching higher
          else leftSide = currentIndex + 1;
      }
  }

  /// @notice Records a new TWAB for `_user`.
  /// @param _user Address of the user whose TWAB is being recorded.
  function _newTwab(address _user) internal {
    uint32 currentTimestamp = uint32(block.timestamp);
    uint256 twabIndex = _mostRecentTwabIndexOfUser(_user);
    Twab memory lastTwab = twabs[_user][twabIndex];

    // If a TWAB already exists at this timestamp, then we don't need to update values
    // This is to avoid recording a new TWAB if several transactions happen in the same block
    if (lastTwab.timestamp == currentTimestamp) {
      return;
    }

    // New twab = last twab balance (or zero) + (previous user balance * elapsed seconds)
    uint32 elapsedSeconds = currentTimestamp - lastTwab.timestamp;
    uint224 newTwabBalance = (lastTwab.balance + (balanceOf(_user) * elapsedSeconds)).toUint224();

    // Record new TWAB
    Twab memory newTwab = Twab ({
      balance: newTwabBalance,
      timestamp: currentTimestamp
    });

    twabs[_user][_getTwabIndex(twabIndex + 1)] = newTwab;
    mostRecentTwabIndex[_user] = _getTwabIndex(twabIndex + 2);

    emit NewTwab(_user, newTwab);
  }

  /// @notice Overridding of the `_beforeTokenTransfer` function of the base ERC20Upgradeable contract.
  /// @dev Hook that is called before any transfer of tokens. This includes minting and burning.
  /// @param _from Sender address.
  /// @param _to Receiver address.
  function _beforeTokenTransfer(address _from, address _to, uint256) internal override {
    if (_from != address(0)) {
      _newTwab(_from);
    }

    if (_to != address(0)) {
      _newTwab(_to);
    }
  }

  /// @notice Retrieves `_user` TWAB balance at `_target`.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  /// @return uint256 `_user` TWAB balance at `_target`.
  function _getBalance(address _user, uint32 _target) internal view returns (uint256) {
    uint256 index = _mostRecentTwabIndexOfUser(_user);
    uint32 time = uint32(block.timestamp);
    uint32 targetTimestamp = _target > time ? time : _target;

    Twab memory afterOrAt;
    Twab memory beforeOrAt = twabs[_user][index];

    // If `targetTimestamp` is chronologically at or after the newest TWAB, we can early return
    if (beforeOrAt.timestamp.lte(targetTimestamp, time)) {
      return balanceOf(_user);
    }

    // Now, set before to the oldest TWAB
    beforeOrAt = twabs[_user][_getTwabIndex(index + 1)];
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

    for(uint256 i =0; i < length; i++){
      balances[i] = _getBalance(_user, _targets[i]);
    }

    return balances;
  }

  /// @notice Claim `_user` winning draws.
  /// @dev This function can be called on behalf of a user.
  /// @param _user User address to claim winning draws for.
  /// @param _claimable Claimable interface to call `claim` method on.
  /// @param _timestamps TWAB `_timestamps` array to get user balances by passing it to `_getBalance` function.
  /// @param _picks Encoded array of user picks.
  /// @return uint256 total amount of tokens claimed.
  function claim(address _user, IClaimable _claimable, uint256[] calldata _timestamps, bytes calldata _picks) external override returns (uint256) {
    uint256 timestampsLength = _timestamps.length;
    uint256[] memory timestampBalances = new uint256[](timestampsLength);

    for (uint256 i; i < timestampsLength; i++) {
      timestampBalances[i] = _getBalance(_user, uint32(_timestamps[i]));
    }

    return _claimable.claim(_user, _timestamps, timestampBalances, _picks);
  }

}
