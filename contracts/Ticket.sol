// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "hardhat/console.sol";

import "./libraries/OverflowSafeComparator.sol";
import "./libraries/TwabLibrary.sol";
import "./interfaces/TicketInterface.sol";
import "./import/token/ControlledToken.sol";

/// @title Ticket contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract Ticket is ControlledToken, OwnableUpgradeable, TicketInterface {
  uint16 public constant MAX_CARDINALITY = 4;

  uint32 public constant TWAB_LIFETIME = 8 weeks;

  using SafeERC20Upgradeable for IERC20Upgradeable;
  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;
  using TwabLibrary for TwabLibrary.Twab[MAX_CARDINALITY];

  /// @notice Amount packed with most recent TWAB index.
  /// @param amount Current `amount`.
  /// @param nextTwabIndex Next TWAB index of twab circular buffer.
  struct AmountWithTwabIndex {
    uint224 amount;
    uint16 nextTwabIndex;
    uint16 cardinality;
  }

  /// @notice Emitted when ticket is initialized.
  /// @param name Ticket name (eg: PoolTogether Dai Ticket (Compound)).
  /// @param symbol Ticket symbol (eg: PcDAI).
  /// @param decimals Ticket decimals.
  /// @param controller Token controller address.
  event TicketInitialized(
    string name,
    string symbol,
    uint8 decimals,
    TokenControllerInterface controller
  );

  /// @notice Emitted when a new TWAB has been recorded.
  /// @param user Ticket holder address.
  /// @param newTwab Updated TWAB of a ticket holder after a successful TWAB recording.
  event NewUserTwab(
    address indexed user,
    TwabLibrary.Twab newTwab
  );

  /// @notice Emitted when a new total supply TWAB has been recorded.
  /// @param newTotalSupplyTwab Updated TWAB of tickets total supply after a successful total supply TWAB recording.
  event NewTotalSupplyTwab(
    TwabLibrary.Twab newTotalSupplyTwab
  );

  /// @notice Record of token holders TWABs for each account.
  mapping (address => TwabLibrary.Twab[MAX_CARDINALITY]) public usersTwabs;

  /// @notice ERC20 ticket token decimals.
  uint8 private _decimals;

  /// @notice Record of token holders balance and most recent TWAB index.
  mapping(address => AmountWithTwabIndex) internal _usersBalanceWithTwabIndex;

  /// @notice Record of tickets total supply TWABs.
  TwabLibrary.Twab[MAX_CARDINALITY] public totalSupplyTwabs;

  /// @notice Record of tickets total supply and most recent TWAB index.
  AmountWithTwabIndex internal _totalSupplyWithTwabIndex;

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalanceAt(address _user, uint32 _target) external override view returns (uint256) {
    return _getBalanceAt(_user, _target);
  }

  function getAverageBalanceBetween(address _user, uint32 _startTime, uint32 _endTime) external override view returns (uint256) {
    return _getAverageBalanceBetween(_user, _startTime, _endTime);
  }

  function _getAverageBalanceBetween(address _user, uint32 _startTime, uint32 _endTime) internal view returns (uint256) {
    AmountWithTwabIndex memory amount = _usersBalanceWithTwabIndex[_user];
    uint16 card = _minCardinality(amount.cardinality);
    uint16 recentIndex = TwabLibrary.mostRecentIndex(amount.nextTwabIndex, card);
    return TwabLibrary.getAverageBalanceBetween(
      usersTwabs[_user],
      _balanceOf(_user).toUint224(),
      recentIndex,
      _startTime,
      _endTime,
      card
    );
  }

  /// @notice Retrieves `_user` TWAB balances.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] `_user` TWAB balances.
  function getBalancesAt(address _user, uint32[] calldata _targets) external override view returns (uint256[] memory) {
    uint256 length = _targets.length;
    uint256[] memory balances = new uint256[](length);

    AmountWithTwabIndex memory amount = _usersBalanceWithTwabIndex[_user];
    uint16 card = _minCardinality(amount.cardinality);
    uint16 twabIndex = TwabLibrary.mostRecentIndex(amount.nextTwabIndex, card);

    TwabLibrary.Twab[MAX_CARDINALITY] storage twabs = usersTwabs[_user];
    uint224 currentBalance = _balanceOf(_user).toUint224();

    for(uint256 i = 0; i < length; i++){
      balances[i] = twabs.getBalanceAt(_targets[i], currentBalance, twabIndex, card);
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

  function _increaseBalance(address _user, uint256 _amount) internal {
    AmountWithTwabIndex memory amountWithTwabIndex = _usersBalanceWithTwabIndex[_user];
    _newUserBalance(amountWithTwabIndex, _user, (amountWithTwabIndex.amount + _amount).toUint224());
  }

  function _decreaseBalance(address _user, uint256 _amount, string memory _message) internal {
    AmountWithTwabIndex memory amountWithTwabIndex = _usersBalanceWithTwabIndex[_user];
    require(amountWithTwabIndex.amount >= _amount, _message);

    _newUserBalance(amountWithTwabIndex, _user, (amountWithTwabIndex.amount - _amount).toUint224());
  }

  function _newUserBalance(
    AmountWithTwabIndex memory amountWithTwabIndex,
    address _user,
    uint224 _newBalance
  ) internal {
    uint16 cardinality = _minCardinality(amountWithTwabIndex.cardinality);
    uint32 currentTimestamp = uint32(block.timestamp);

    // console.log("amountWithTwabIndex.nextTwabIndex: ");
    // console.log(amountWithTwabIndex.nextTwabIndex);
    // console.log("cardinality: ");
    // console.log(cardinality);

    TwabLibrary.Twab memory newestTwab = usersTwabs[_user][TwabLibrary.mostRecentIndex(amountWithTwabIndex.nextTwabIndex, cardinality)];

    TwabLibrary.Twab memory oldestTwab = usersTwabs[_user][TwabLibrary.wrapCardinality(amountWithTwabIndex.nextTwabIndex, cardinality)];
    // If the TWAB is not initialized we go to the beginning of the TWAB circular buffer at index 0
    if (oldestTwab.timestamp == 0) {
      oldestTwab = usersTwabs[_user][0];
    }

    // If there is no twab, or if we haven't exceed the twab lifetime then add a new twab.
    if (oldestTwab.timestamp == 0 || newestTwab.timestamp - oldestTwab.timestamp < TWAB_LIFETIME) {
      cardinality = cardinality < MAX_CARDINALITY ? cardinality + 1 : MAX_CARDINALITY;
    }

    (TwabLibrary.Twab memory newTwab, uint16 nextAvailableTwabIndex) = TwabLibrary.nextTwab(
      newestTwab,
      amountWithTwabIndex.amount,
      amountWithTwabIndex.nextTwabIndex,
      cardinality,
      currentTimestamp
    );

    // We don't record a new TWAB if a TWAB already exists at the same timestamp
    // So we don't emit `NewUserTwab` since no new TWAB has been recorded
    if (nextAvailableTwabIndex != amountWithTwabIndex.nextTwabIndex) {
      usersTwabs[_user][amountWithTwabIndex.nextTwabIndex] = newTwab;
      emit NewUserTwab(_user, newTwab);
    }

    _usersBalanceWithTwabIndex[_user] = AmountWithTwabIndex({
      amount: _newBalance,
      nextTwabIndex: nextAvailableTwabIndex,
      cardinality: cardinality
    });
  }

  // /// @notice Records a new TWAB for `_user`.
  // /// @param _user Address of the user whose TWAB is being recorded.
  // /// @param _nextTwabIndex next TWAB index to record to.
  // /// @return uint16 next available TWAB index after recording.
  // function _newUserBalance(address _user, AmountWithTwabIndex memory amountWithTwabIndex) internal returns (AmountWithTwabIndex memory) {
  //   uint32 currentTimestamp = uint32(block.timestamp);
  //   TwabLibrary.Twab memory lastTwab = usersTwabs[_user][TwabLibrary.mostRecentIndex(_nextTwabIndex, MAX_CARDINALITY)];
  //   (TwabLibrary.Twab memory newTwab, uint16 nextAvailableTwabIndex) = TwabLibrary.nextTwab(
  //     lastTwab,
  //     _balanceOf(_user),
  //     _nextTwabIndex,
  //     MAX_CARDINALITY,
  //     currentTimestamp
  //   );

  //   // We don't record a new TWAB if a TWAB already exists at the same timestamp
  //   // So we don't emit `NewUserTwab` since no new TWAB has been recorded
  //   if (nextAvailableTwabIndex != _nextTwabIndex) {
  //     usersTwabs[_user][_nextTwabIndex] = newTwab;
  //     emit NewUserTwab(_user, newTwab);
  //   }

  //   return nextAvailableTwabIndex;
  // }

  /// @notice Records a new total supply TWAB.
  /// @param _nextTwabIndex next TWAB index to record to.
  /// @return uint16 next available TWAB index after recording.
  function _newTotalSupplyTwab(uint16 _nextTwabIndex) internal returns (uint16) {
    uint32 currentTimestamp = uint32(block.timestamp);
    TwabLibrary.Twab memory lastTwab = totalSupplyTwabs[TwabLibrary.mostRecentIndex(_nextTwabIndex, MAX_CARDINALITY)];
    (TwabLibrary.Twab memory newTwab, uint16 nextAvailableTwabIndex) = TwabLibrary.nextTwab(
      lastTwab,
      _ticketTotalSupply(),
      _nextTwabIndex,
      MAX_CARDINALITY,
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
  function _getBalanceAt(address _user, uint32 _target) internal view returns (uint256) {
    AmountWithTwabIndex memory amount = _usersBalanceWithTwabIndex[_user];
    uint16 cardinality = _minCardinality(amount.cardinality);
    uint16 recentIndex = TwabLibrary.mostRecentIndex(amount.nextTwabIndex, cardinality);
    return usersTwabs[_user].getBalanceAt(_target, _balanceOf(_user), recentIndex, cardinality);
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function _getTotalSupply(uint32 _target) internal view returns (uint256) {
    AmountWithTwabIndex memory amount = _totalSupplyWithTwabIndex;
    uint16 cardinality = _minCardinality(amount.cardinality);
    uint16 recentIndex = TwabLibrary.mostRecentIndex(amount.nextTwabIndex, cardinality);
    return totalSupplyTwabs.getBalanceAt(_target, _ticketTotalSupply(), recentIndex, cardinality);
  }

  function _minCardinality(uint16 cardinality) internal pure returns (uint16) {
    return cardinality > 0 ? cardinality : 1;
  }

  /// @notice Initializes Ticket with passed parameters.
  /// @param _name ERC20 ticket token name.
  /// @param _symbol ERC20 ticket token symbol.
  /// @param decimals_ ERC20 ticket token decimals.
  function initialize (
    string calldata _name,
    string calldata _symbol,
    uint8 decimals_,
    TokenControllerInterface _controller
  ) public virtual override initializer {
    __ERC20_init(_name, _symbol);
    __ERC20Permit_init("PoolTogether Ticket");

    require(decimals_ > 0, "Ticket/decimals-gt-zero");
    _decimals = decimals_;

    __Ownable_init();

    require(address(_controller) != address(0), "Ticket/controller-not-zero-address");
    ControlledToken.initialize(_name, _symbol, _decimals, _controller);

    emit TicketInitialized(_name, _symbol, decimals_, _controller);
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
    return _ticketTotalSupply();
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

    _decreaseBalance(_sender, amount, "ERC20: transfer amount exceeds balance");
    _increaseBalance(_recipient, amount);

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

    AmountWithTwabIndex memory ticketTotalSupply = _totalSupplyWithTwabIndex;
    _totalSupplyWithTwabIndex = AmountWithTwabIndex({
      amount: (uint256(ticketTotalSupply.amount) + amount).toUint224(),
      nextTwabIndex: _newTotalSupplyTwab(ticketTotalSupply.nextTwabIndex),
      cardinality: MAX_CARDINALITY // maxed
    });

    _increaseBalance(_to, amount);

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

    _decreaseBalance(_from, _amount, "ERC20: burn amount exceeds balance");

    AmountWithTwabIndex memory ticketTotalSupply = _totalSupplyWithTwabIndex;
    _totalSupplyWithTwabIndex = AmountWithTwabIndex({
      amount: ticketTotalSupply.amount - amount,
      nextTwabIndex: _newTotalSupplyTwab(ticketTotalSupply.nextTwabIndex),
      cardinality: MAX_CARDINALITY
    });

    emit Transfer(_from, address(0), _amount);

    _afterTokenTransfer(_from, address(0), _amount);
  }

}
