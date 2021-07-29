// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./interfaces/ITicket.sol";
import "./libraries/Math.sol";

/// @title Ticket contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract Ticket is ITicket, ERC20PermitUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using Math for uint32;
  using SafeCastUpgradeable for uint256;

  /// @notice Tracks total supply of tickets.
  uint256 private _totalSupply;

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

  /// @notice Balance of a ticket holder packed with most recent TWAB index.
  /// @param balance Current user balance.
  /// @param twabIndex Last TWAB index of user.
  struct BalanceWithTwabIndex {
    uint240 balance;
    uint16 twabIndex;
  }

  /// @notice Record of token holders balance and most recent TWAB index.
  mapping(address => BalanceWithTwabIndex) private _balancesWithTwabIndex;

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

  /// @notice Returns the ERC20 ticket token total supply.
  /// @return uint256 Total supply of the ERC20 ticket token.
  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
  }

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint240 `_user` ticket token balance.
  function balanceOf(address _user) public view virtual override returns (uint256) {
    return _balancesWithTwabIndex[_user].balance;
  }

  /// @notice Returns TWAB index.
  /// @dev `twabs` is a circular buffer of `CARDINALITY` size equal to 32. So the array goes from 0 to 31.
  /// @dev In order to navigate the circular buffer, we need to use the modulo operator.
  /// @dev For example, if `_index` is equal to 32, `_index % CARDINALITY` will return 0 and will point to the first element of the array.
  /// @param _index Index used to navigate through `twabs` circular buffer.
  function _getTwabIndex(uint256 _index) internal pure returns (uint16) {
    return uint16(_index % CARDINALITY);
  }

  /// @notice Returns the `mostRecentTwabIndex` of a `_user`.
  /// @param _user Address of the user whose most recent TWAB index is being fetched.
  /// @return uint256 `mostRecentTwabIndex` of `_user`.
  function _mostRecentTwabIndexOfUser(address _user) internal view returns (uint16) {
    return _balancesWithTwabIndex[_user].twabIndex;
    // TODO: fix mostRecentTwabIndex so that getBalances doesn't run out of gas
    // return _getTwabIndex(_balancesWithTwabIndex[_user].twabIndex + CARDINALITY - 1);
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
      uint16 twabIndex = _mostRecentTwabIndexOfUser(_user);

      uint256 leftSide = _getTwabIndex(twabIndex + 1); // Oldest TWAB
      uint256 rightSide = leftSide + CARDINALITY - 1; // Newest TWAB
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
  /// @param _twabIndex Index of the TWAB being recorded.
  /// @return most recent TWAB index of `_user`.
  function _newTwab(address _user, uint16 _twabIndex) internal returns (uint16) {
    uint32 currentTimestamp = uint32(block.timestamp);
    Twab memory lastTwab = twabs[_user][_twabIndex];

    // If a TWAB already exists at this timestamp, then we don't need to update values
    // This is to avoid recording a new TWAB if several transactions happen in the same block
    if (lastTwab.timestamp == currentTimestamp) {
      return _twabIndex;
    }

    // New twab = last twab balance (or zero) + (previous user balance * elapsed seconds)
    uint32 elapsedSeconds = currentTimestamp - lastTwab.timestamp;
    uint224 newTwabBalance = (lastTwab.balance + (balanceOf(_user) * elapsedSeconds)).toUint224();

    // Record new TWAB
    Twab memory newTwab = Twab ({
      balance: newTwabBalance,
      timestamp: currentTimestamp
    });

    uint16 nextTwabIndex = _getTwabIndex(_twabIndex + 1);
    twabs[_user][nextTwabIndex] = newTwab;

    emit NewTwab(_user, newTwab);

    return nextTwabIndex;
  }

  /// @notice Overridding of the `_transfer` function of the base ERC20Upgradeable contract.
  /// @dev `_sender` cannot be the zero address.
  /// @dev `_recipient` cannot be the zero address.
  /// @dev `_sender` must have a balance of at least `_amount`.
  /// @param _sender Address of the `_sender`that will send `_amount` of tokens.
  /// @param _recipient Address of the `_recipient`that will receive `_amount` of tokens.
  /// @param _amount Amount of tokens to be transferred from `_sender` to `_recipient`.
  function _transfer(
    address _sender,
    address _recipient,
    uint256 _amount
  ) internal override virtual {
    require(_sender != address(0), "ERC20: transfer from the zero address");
    require(_recipient != address(0), "ERC20: transfer to the zero address");

    _beforeTokenTransfer(_sender, _recipient, _amount);

    BalanceWithTwabIndex memory sender = _balancesWithTwabIndex[_sender];
    require(sender.balance >= uint240(_amount), "ERC20: transfer amount exceeds balance");
    unchecked {
        _balancesWithTwabIndex[_sender] = BalanceWithTwabIndex({
          balance: sender.balance - uint240(_amount),
          twabIndex: _newTwab(_sender, sender.twabIndex)
        });
    }

    BalanceWithTwabIndex memory recipient = _balancesWithTwabIndex[_recipient];
    _balancesWithTwabIndex[_recipient] = BalanceWithTwabIndex({
      balance: recipient.balance + uint240(_amount),
      twabIndex: _newTwab(_recipient, recipient.twabIndex)
    });

    emit Transfer(_sender, _recipient, _amount);

    _afterTokenTransfer(_sender, _recipient, _amount);
  }

  /// @notice Overridding of the `_mint` function of the base ERC20Upgradeable contract.
  /// @dev `_to` cannot be the zero address.
  /// @param _to Address that will be minted `_amount` of tokens.
  /// @param _amount Amount of tokens to be minted to `_to`.
  function _mint(address _to, uint256 _amount) internal virtual override {
      require(_to != address(0), "ERC20: mint to the zero address");

      _beforeTokenTransfer(address(0), _to, _amount);

      _totalSupply += _amount;

      BalanceWithTwabIndex memory user = _balancesWithTwabIndex[_to];
      _balancesWithTwabIndex[_to] = BalanceWithTwabIndex({
        balance: user.balance + uint240(_amount),
        twabIndex: _newTwab(_to, user.twabIndex)
      });

      emit Transfer(address(0), _to, _amount);

      _afterTokenTransfer(address(0), _to, _amount);
  }

  /// @notice Overridding of the `_burn` function of the base ERC20Upgradeable contract.
  /// @dev `_from` cannot be the zero address.
  /// @dev `_from` must have at least `_amount` of tokens.
  /// @param _from Address that will be burned `_amount` of tokens.
  /// @param _amount Amount of tokens to be burnt from `_from`.
  function _burn(address _from, uint256 _amount) internal virtual override {
    require(_from != address(0), "ERC20: burn from the zero address");

    _beforeTokenTransfer(_from, address(0), _amount);

    BalanceWithTwabIndex memory user = _balancesWithTwabIndex[_from];
    require(user.balance >= uint240(_amount), "ERC20: burn amount exceeds balance");
    unchecked {
      _balancesWithTwabIndex[_from] = BalanceWithTwabIndex({
        balance: user.balance - uint240(_amount),
        twabIndex: _newTwab(_from, user.twabIndex)
      });
    }

    _totalSupply -= _amount;

    emit Transfer(_from, address(0), _amount);

    _afterTokenTransfer(_from, address(0), _amount);
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

    for(uint256 i = 0; i < length; i++){
      balances[i] = _getBalance(_user, _targets[i]);
    }

    return balances;
  }

}
