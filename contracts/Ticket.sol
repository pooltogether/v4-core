// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./libraries/OverflowSafeComparator.sol";
import "./libraries/TwabLibrary.sol";
import "./interfaces/ITicket.sol";
import "./ControlledToken.sol";

/// @title An ERC20 token that allows you to see user's past balances, and average balance held between timestamps.
/// @author PoolTogether Inc.
contract Ticket is ControlledToken, ITicket {
  /// @notice The minimum length of time a twab should exist.
  /// @dev Once the twab ttl expires, its storage slot is recycled.
  uint32 public constant TWAB_TIME_TO_LIVE = 24 weeks;
  /// @notice The maximum number of twab entries
  uint16 public constant MAX_CARDINALITY = 65535;

  using SafeERC20 for IERC20Upgradeable;
  using SafeCast for uint256;

  /// @notice A struct containing details for an Account
  /// @param balance The current balance for an Account
  /// @param nextTwabIndex The next available index to store a new twab
  /// @param cardinality The number of recorded twabs (plus one!)
  struct AccountDetails {
    uint224 balance;
    uint16 nextTwabIndex;
    uint16 cardinality;
  }

  /// @notice Combines account details with their twab history
  /// @param details The account details
  /// @param twabs The history of twabs for this account
  struct Account {
    AccountDetails details;
    TwabLibrary.Twab[MAX_CARDINALITY] twabs;
  }

  /// @notice Record of token holders TWABs for each account.
  mapping (address => Account) internal userTwabs;

  /// @notice ERC20 ticket token decimals.
  uint8 private _decimals;

  /// @notice Record of tickets total supply and most recent TWAB index.
  Account internal totalSupplyTwab;

  /// @notice Mapping of delegates.  Each address can delegate their ticket power to another.
  mapping(address => address) delegates;

  /// @notice Each address's balance
  mapping(address => uint256) balances;

  /* ============ Constructor ============ */

  /// @notice Constructs Ticket with passed parameters.
  /// @param _name ERC20 ticket token name.
  /// @param _symbol ERC20 ticket token symbol.
  /// @param decimals_ ERC20 ticket token decimals.
  constructor (
    string memory _name,
    string memory _symbol,
    uint8 decimals_,
    address _controller
  ){

    __ERC20_init(_name, _symbol);
    __ERC20Permit_init("PoolTogether Ticket");

    require(decimals_ > 0, "Ticket/decimals-gt-zero");
    _decimals = decimals_;

    require(_controller != address(0), "Ticket/controller-not-zero-address");

    // ControlledToken.initialize(_name, _symbol, decimals_, _controller);

    emit TicketInitialized(_name, _symbol, decimals_, _controller);
  }

    /* ============ External Functions ============ */

  /// @notice Gets a users twap context.  This is a struct with their balance, next twab index, and cardinality.
  /// @param _user The user for whom to fetch the TWAB context
  /// @return The TWAB context, which includes { balance, nextTwabIndex, cardinality }
  function getAccountDetails(address _user) external view returns (AccountDetails memory) {
    return userTwabs[_user].details;
  }

  /// @notice Gets the TWAB at a specific index for a user.
  /// @param _user The user for whom to fetch the TWAB
  /// @param _index The index of the TWAB to fetch
  /// @return The TWAB, which includes the twab amount and the timestamp.
  function getTwab(address _user, uint16 _index) external view returns (TwabLibrary.Twab memory) {
    return userTwabs[_user].twabs[_index];
  }

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalanceAt(address _user, uint256 _target) external override view returns (uint256) {
    Account storage account = userTwabs[_user];
    return _getBalanceAt(account.twabs, account.details, _target);
  }

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getBalanceAt(TwabLibrary.Twab[MAX_CARDINALITY] storage _twabs, AccountDetails memory _details, uint256 _target) internal view returns (uint256) {
    return TwabLibrary.getBalanceAt(
      _details.cardinality,
      _details.nextTwabIndex,
      _twabs,
      _details.balance,
      uint32(_target),
      uint32(block.timestamp)
    );
  }

  /// @notice Calculates the average balance held by a user for given time frames.
  /// @param user The user whose balance is checked
  /// @param startTimes The start time of the time frame.
  /// @param endTimes The end time of the time frame.
  /// @return The average balance that the user held during the time frame.
  function getAverageBalancesBetween(address user, uint32[] calldata startTimes, uint32[] calldata endTimes) external override view
    returns (uint256[] memory)
  {
    require(startTimes.length == endTimes.length, "Ticket/start-end-times-length-match");
    Account storage account = userTwabs[user];
    uint256[] memory averageBalances = new uint256[](startTimes.length);

    for (uint i = 0; i < startTimes.length; i++) {
      averageBalances[i] = _getAverageBalanceBetween(account.twabs, account.details, startTimes[i], endTimes[i]);
    }
    return averageBalances;
  }

  /// @notice Calculates the average total supply balance for a set of given time frames.
  /// @param startTimes Array of start times
  /// @param endTimes Array of end times
  /// @return The average total supplies held during the time frame.
  function getAverageTotalSuppliesBetween(uint32[] calldata startTimes, uint32[] calldata endTimes) external override view
    returns (uint256[] memory)
  {
    require(startTimes.length == endTimes.length, "Ticket/start-end-times-length-match");
    Account storage _totalSupplyTwab = totalSupplyTwab;
    uint256[] memory averageTotalSupplies = new uint256[](startTimes.length);

    for (uint i = 0; i < startTimes.length; i++) {
      averageTotalSupplies[i] = _getAverageBalanceBetween(_totalSupplyTwab.twabs, _totalSupplyTwab.details, startTimes[i], endTimes[i]);
    }
    return averageTotalSupplies;
  }

  /// @notice Calculates the average balance held by a user for a given time frame.
  /// @param _user The user whose balance is checked
  /// @param _startTime The start time of the time frame.
  /// @param _endTime The end time of the time frame.
  /// @return The average balance that the user held during the time frame.
  function getAverageBalanceBetween(address _user, uint256 _startTime, uint256 _endTime) external override view returns (uint256) {
    Account storage account = userTwabs[_user];
    return _getAverageBalanceBetween(account.twabs, account.details, uint32(_startTime), uint32(_endTime));
  }

  /// @notice Calculates the average balance held by a user for a given time frame.
  /// @param _startTime The start time of the time frame.
  /// @param _endTime The end time of the time frame.
  /// @return The average balance that the user held during the time frame.
  function _getAverageBalanceBetween(TwabLibrary.Twab[MAX_CARDINALITY] storage _twabs, AccountDetails memory _details, uint32 _startTime, uint32 _endTime)
   internal view returns (uint256) {
    return TwabLibrary.getAverageBalanceBetween(
      _details.cardinality,
      _details.nextTwabIndex,
      _twabs,
      _details.balance,
      _startTime,
      _endTime,
      uint32(block.timestamp)
    );
  }

  /// @notice Retrieves `_user` TWAB balances.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] `_user` TWAB balances.
  function getBalancesAt(address _user, uint32[] calldata _targets) external override view returns (uint256[] memory) {
    uint256 length = _targets.length;
    uint256[] memory balances = new uint256[](length);

    Account storage twabContext = userTwabs[_user];
    AccountDetails memory details = twabContext.details;

    for(uint256 i = 0; i < length; i++) {
      balances[i] = _getBalanceAt(twabContext.twabs, details, _targets[i]);
    }

    return balances;
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getTotalSupply(uint32 _target) override external view returns (uint256) {
    return _getBalanceAt(totalSupplyTwab.twabs, totalSupplyTwab.details, _target);
  }

  /// @notice Retrieves ticket TWAB `totalSupplies`.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] ticket TWAB `totalSupplies`.
  function getTotalSupplies(uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory totalSupplies = new uint256[](length);

    AccountDetails memory details = totalSupplyTwab.details;

    for(uint256 i = 0; i < length; i++) {
      totalSupplies[i] = _getBalanceAt(totalSupplyTwab.twabs, details, _targets[i]);
    }

    return totalSupplies;
  }

  function delegateOf(address _user) external view returns (address) {
    return delegates[_user];
  }

  /// @notice Returns the ERC20 ticket token decimals.
  /// @dev This value should be equal to the decimals of the token used to deposit into the pool.
  /// @return uint8 decimals.
  function decimals() public view virtual override returns (uint8) {
    return _decimals;
  }

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint224 `_user` ticket token balance.
  function balanceOf(address _user) public view override returns (uint256) {
    return _balanceOf(_user);
  }

  /// @notice Returns the ERC20 ticket token total supply.
  /// @return uint256 Total supply of the ERC20 ticket token.
  function totalSupply() public view virtual override returns (uint256) {
    return totalSupplyTwab.details.balance;
  }

  function delegate(address to) external virtual {
    uint224 balance = uint224(_balanceOf(msg.sender));
    address currentDelegate = delegates[msg.sender];

    if (currentDelegate != address(0)) {
      _decreaseUserTwab(msg.sender, currentDelegate, balance);
    } else {
      _decreaseUserTwab(msg.sender, msg.sender, balance);
    }

    if (to != address(0)) {
      _increaseUserTwab(msg.sender, to, balance);
    } else {
      _increaseUserTwab(msg.sender, msg.sender, balance);
    }

    delegates[msg.sender] = to;

    emit Delegated(msg.sender, to);
  }

  /* ============ Internal Functions ============ */

  /// @notice Calculates the average balance held by a user for a given time frame.
  /// @param _startTime The start time of the time frame.
  /// @param _endTime The end time of the time frame.
  /// @return The average balance that the user held during the time frame.
  function _getAverageBalanceBetween(TwabLibrary.Twab[MAX_CARDINALITY] storage _twabs, AccountDetails memory _details, uint32 _startTime, uint32 _endTime)
    internal view returns (uint256) {
    return TwabLibrary.getAverageBalanceBetween(
      _details.cardinality,
      _details.nextTwabIndex,
      _twabs,
      _details.balance,
      _startTime,
      _endTime,
      uint32(block.timestamp)
    );
  }

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getBalanceAt(TwabLibrary.Twab[MAX_CARDINALITY] storage _twabs, AccountDetails memory _details, uint256 _target)
    internal view returns (uint256) {
    return TwabLibrary.getBalanceAt(
      _details.cardinality,
      _details.nextTwabIndex,
      _twabs,
      _details.balance,
      uint32(_target),
      uint32(block.timestamp)
    );
  }

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint256 `_user` ticket token balance.
  function _balanceOf(address _user) internal view returns (uint256) {
    return balances[_user];
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

    uint224 amount = uint224(_amount);

    _beforeTokenTransfer(_sender, _recipient, _amount);

    if (_sender != _recipient) {

      // standard balance update
      uint256 senderBalance = balances[_sender];
      require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
      unchecked {
          balances[_sender] = senderBalance - amount;
      }
      balances[_recipient] += amount;

      // history update
      address senderDelegate = delegates[_sender];
      if (senderDelegate != address(0)) {
        _decreaseUserTwab(_sender, senderDelegate, _amount);
      } else {
        _decreaseUserTwab(_sender, _sender, _amount);
      }

      // history update
      address recipientDelegate = delegates[_recipient];
      if (recipientDelegate != address(0)) {
        _increaseUserTwab(_recipient, recipientDelegate, amount);
      } else {
        _increaseUserTwab(_recipient, _recipient, amount);
      }

    }

    emit Transfer(_sender, _recipient, _amount);

    _afterTokenTransfer(_sender, _recipient, _amount);
  }

  /// @notice Overridding of the `_mint` function of the base ERC20Upgradeable contract.
  /// @dev `_to` cannot be the zero address.
  /// @param _to Address that will be minted `_amount` of tokens.
  /// @param _amount Amount of tokens to be minted to `_to`.
  function _mint(address _to, uint256 _amount) internal virtual override {
    require(_to != address(0), "ERC20: mint to the zero address");

    uint224 amount = _amount.toUint224();

    _beforeTokenTransfer(address(0), _to, _amount);

    balances[_to] += amount;

    (TwabLibrary.Twab memory totalSupply, bool tsIsNew) = increaseTwab(totalSupplyTwab, amount);
    if (tsIsNew) {
      emit NewTotalSupplyTwab(totalSupply);
    }

    address toDelegate = delegates[_to];
    if (toDelegate != address(0)) {
      _increaseUserTwab(_to, toDelegate, amount);
    } else {
      _increaseUserTwab(_to, _to, amount);
    }

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

    uint224 amount = _amount.toUint224();

    _beforeTokenTransfer(_from, address(0), _amount);

    (TwabLibrary.Twab memory tsTwab, bool tsIsNew) = decreaseTwab(
      totalSupplyTwab,
      amount,
      "ERC20: burn amount exceeds balance"
    );
    if (tsIsNew) {
      emit NewTotalSupplyTwab(tsTwab);
    }

    uint256 accountBalance = balances[_from];
    require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
        balances[_from] = accountBalance - amount;
    }

    address fromDelegate = delegates[_from];
    if (fromDelegate != address(0)) {
      _decreaseUserTwab(_from, fromDelegate, amount);
    } else {
      _decreaseUserTwab(_from, _from, amount);
    }

    emit Transfer(_from, address(0), _amount);

    _afterTokenTransfer(_from, address(0), _amount);
  }

  function _increaseUserTwab(
    address _holder,
    address _user,
    uint256 _amount
  ) internal {
    Account storage _account = userTwabs[_user];
    // console.log("_increaseUserTwab ", _user);
    (TwabLibrary.Twab memory twab, bool isNew) = increaseTwab(_account, _amount);
    if (isNew) {
      // console.log("!!! new twab: ", twab.timestamp);
      emit NewUserTwab(_holder, _user, twab);
    }
  }

  function _decreaseUserTwab(
    address _holder,
    address _user,
    uint256 _amount
  ) internal {
    Account storage _account = userTwabs[_user];
    // console.log("_decreaseUserTwab ", _user);
    (TwabLibrary.Twab memory twab, bool isNew) = decreaseTwab(_account, _amount, "ERC20: burn amount exceeds balance");
    if (isNew) {
      // console.log("!!! new twab: ", twab.timestamp);
      emit NewUserTwab(_holder, _user, twab);
    }
  }

  /// @notice Increases an account's balance and records a new twab.
  /// @param _account The account whose balance will be increased
  /// @param _amount The amount to increase the balance by
  /// @return twab The user's latest TWAB
  /// @return isNew Whether the TWAB is new
  function increaseTwab(
    Account storage _account,
    uint256 _amount
  ) internal returns (TwabLibrary.Twab memory twab, bool isNew) {
    uint16 nextTwabIndex;
    uint16 cardinality;
    AccountDetails memory details = _account.details;
    (nextTwabIndex, cardinality, twab, isNew) = TwabLibrary.update(
      details.balance,
      details.nextTwabIndex,
      details.cardinality,
      _account.twabs,
      uint32(block.timestamp),
      TWAB_TIME_TO_LIVE
    );
    _account.details = AccountDetails({
      balance: (details.balance + _amount).toUint224(),
      nextTwabIndex: nextTwabIndex,
      cardinality: cardinality
    });
  }

  /// @notice Decreases an account's balance and records a new twab.
  /// @param _account The account whose balance will be decreased
  /// @param _amount The amount to decrease the balance by
  /// @param _message The revert message in the event of insufficient balance
  /// @return twab The user's latest TWAB
  /// @return isNew Whether the TWAB is new
  function decreaseTwab(
    Account storage _account,
    uint256 _amount,
    string memory _message
  ) internal returns (TwabLibrary.Twab memory twab, bool isNew) {
    uint16 nextTwabIndex;
    uint16 cardinality;
    AccountDetails memory details = _account.details;
    require(details.balance >= _amount, _message);
    (nextTwabIndex, cardinality, twab, isNew) = TwabLibrary.update(
      details.balance,
      details.nextTwabIndex,
      details.cardinality,
      _account.twabs,
      uint32(block.timestamp),
      TWAB_TIME_TO_LIVE
    );
    _account.details = AccountDetails({
      balance: (details.balance - _amount).toUint224(),
      nextTwabIndex: nextTwabIndex,
      cardinality: cardinality
    });
  }

}
