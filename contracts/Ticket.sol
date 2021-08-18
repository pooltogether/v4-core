// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "hardhat/console.sol";

import "./libraries/OverflowSafeComparator.sol";
import "./libraries/TwabLibrary.sol";
import "./libraries/TwabContextLibrary.sol";
import "./interfaces/TicketInterface.sol";
import "./import/token/ControlledToken.sol";

/// @title Ticket contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract Ticket is ControlledToken, OwnableUpgradeable, TicketInterface {
  /// @notice How long it takes for TWABs to expire.  After they expire they are overwritten.
  uint32 public constant TWAB_EXPIRY = 8 weeks;

  using SafeERC20Upgradeable for IERC20Upgradeable;
  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;
  using TwabLibrary for TwabLibrary.Twab[4294967296];
  using TwabContextLibrary for TwabContextLibrary.TwabContext;

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
  mapping (address => TwabContextLibrary.TwabContext) internal userTwabs;

  /// @notice ERC20 ticket token decimals.
  uint8 private _decimals;

  /// @notice Record of tickets total supply and most recent TWAB index.
  TwabContextLibrary.TwabContext internal totalSupplyTwab;

  function userBalanceWithTwab(address _user) external view returns (TwabContextLibrary.Context memory) {
    return userTwabs[_user].context;
  }

  function getTwab(address _user, uint16 _index) external view returns (TwabLibrary.Twab memory) {
    return userTwabs[_user].twabs[_index];
  }

  /// @notice Retrieves `_user` TWAB balance.
  /// @param _user Address of the user whose TWAB is being fetched.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getBalanceAt(address _user, uint32 _target) external override view returns (uint256) {
    return _getBalanceAt(_user, _target);
  }

  function _getBalanceAt(address _user, uint32 _target) internal view returns (uint256) {
    return userTwabs[_user].getBalanceAt(_target, uint32(block.timestamp));
  }

  function getAverageBalanceBetween(address _user, uint32 _startTime, uint32 _endTime) external override view returns (uint256) {
    return _getAverageBalanceBetween(_user, _startTime, _endTime);
  }

  function _getAverageBalanceBetween(address _user, uint32 _startTime, uint32 _endTime) internal view returns (uint256) {
    return userTwabs[_user].getAverageBalanceBetween(_startTime, _endTime, uint32(block.timestamp));
  }

  /// @notice Retrieves `_user` TWAB balances.
  /// @param _user Address of the user whose TWABs are being fetched.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] `_user` TWAB balances.
  function getBalancesAt(address _user, uint32[] calldata _targets) external override view returns (uint256[] memory) {
    uint256 length = _targets.length;
    uint256[] memory balances = new uint256[](length);

    TwabContextLibrary.TwabContext storage twabContext = userTwabs[_user];

    for(uint256 i = 0; i < length; i++){
      balances[i] = twabContext.getBalanceAt(_targets[i], uint32(block.timestamp));
    }

    return balances;
  }

  /// @notice Retrieves ticket TWAB `totalSupply`.
  /// @param _target Timestamp at which the reserved TWAB should be for.
  function getTotalSupply(uint32 _target) override external view returns (uint256) {
    return totalSupplyTwab.getBalanceAt(_target, uint32(block.timestamp));
  }

  /// @notice Retrieves ticket TWAB `totalSupplies`.
  /// @param _targets Timestamps at which the reserved TWABs should be for.
  /// @return uint256[] ticket TWAB `totalSupplies`.
  function getTotalSupplies(uint32[] calldata _targets) external view override returns (uint256[] memory){
    uint256 length = _targets.length;
    uint256[] memory totalSupplies = new uint256[](length);

    for(uint256 i = 0; i < length; i++){
      // console.log("getTotalSupplies: %s ", _targets[i]);
      totalSupplies[i] = totalSupplyTwab.getBalanceAt(_targets[i], uint32(block.timestamp));
    }

    return totalSupplies;
  }

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint256 `_user` ticket token balance.
  function _balanceOf(address _user) internal view returns (uint256) {
    return userTwabs[_user].context.balance;
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
    return totalSupplyTwab.context.balance;
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

    uint32 time = uint32(block.timestamp);

    uint224 amount = uint224(_amount);

    _beforeTokenTransfer(_sender, _recipient, _amount);

    if (_sender != _recipient) {
      (TwabLibrary.Twab memory senderTwab, bool senderIsNew) = userTwabs[_sender].decreaseBalance(amount, "ERC20: transfer amount exceeds balance", time, TWAB_EXPIRY);
      if (senderIsNew) {
        emit NewUserTwab(_sender, senderTwab);
      }
      (TwabLibrary.Twab memory recipientTwab, bool recipientIsNew) = userTwabs[_recipient].increaseBalance(amount, time, TWAB_EXPIRY);
      if (recipientIsNew) {
        emit NewUserTwab(_recipient, recipientTwab);
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
    uint32 time = uint32(block.timestamp);

    _beforeTokenTransfer(address(0), _to, _amount);

    (TwabLibrary.Twab memory totalSupply, bool tsIsNew) = totalSupplyTwab.increaseBalance(amount, time, TWAB_EXPIRY);
    if (tsIsNew) {
      emit NewTotalSupplyTwab(totalSupply);
    }
    (TwabLibrary.Twab memory userTwab, bool userIsNew) = userTwabs[_to].increaseBalance(amount, time, TWAB_EXPIRY);
    if (userIsNew) {
      emit NewUserTwab(_to, userTwab);
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
    uint32 time = uint32(block.timestamp);

    _beforeTokenTransfer(_from, address(0), _amount);

    (TwabLibrary.Twab memory tsTwab, bool tsIsNew) = totalSupplyTwab.decreaseBalance(
      amount,
      "ERC20: burn amount exceeds balance",
      time,
      TWAB_EXPIRY
    );
    if (tsIsNew) {
      emit NewTotalSupplyTwab(tsTwab);
    }

    (TwabLibrary.Twab memory userTwab, bool userIsNew) = userTwabs[_from].decreaseBalance(
      amount,
      "ERC20: burn amount exceeds balance",
      time,
      TWAB_EXPIRY
    );
    if (userIsNew) {
      emit NewUserTwab(_from, userTwab);
    }

    emit Transfer(_from, address(0), _amount);

    _afterTokenTransfer(_from, address(0), _amount);
  }

}
