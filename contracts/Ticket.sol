// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./import/token/ControlledToken.sol";
import "./TicketTwab.sol";

/// @title Ticket contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract Ticket is ControlledToken, TicketTwab, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using OverflowSafeComparator for uint32;
  using SafeCastUpgradeable for uint256;

  /// @notice Tracks total supply of tickets.
  uint256 private _totalSupply;

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

  /// @notice ERC20 ticket token decimals.
  uint8 private _decimals;

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

    AmountWithTwabIndex memory sender = _usersBalanceWithTwabIndex[_sender];
    require(sender.amount >= amount, "ERC20: transfer amount exceeds balance");
    unchecked {
        _usersBalanceWithTwabIndex[_sender] = AmountWithTwabIndex({
          amount: sender.amount - amount,
          nextTwabIndex: _newUserTwab(_sender, sender.nextTwabIndex),
          cardinality: CARDINALITY
        });
    }

    AmountWithTwabIndex memory recipient = _usersBalanceWithTwabIndex[_recipient];
    _usersBalanceWithTwabIndex[_recipient] = AmountWithTwabIndex({
      amount: (uint256(recipient.amount) + amount).toUint224(),
      nextTwabIndex: _newUserTwab(_recipient, recipient.nextTwabIndex),
      cardinality: CARDINALITY
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

    uint224 amount = _amount.toUint224();

    _beforeTokenTransfer(address(0), _to, _amount);

    AmountWithTwabIndex memory ticketTotalSupply = _totalSupplyWithTwabIndex;
    _totalSupplyWithTwabIndex = AmountWithTwabIndex({
      amount: (uint256(ticketTotalSupply.amount) + amount).toUint224(),
      nextTwabIndex: _newTotalSupplyTwab(ticketTotalSupply.nextTwabIndex),
      cardinality: CARDINALITY // maxed
    });

    AmountWithTwabIndex memory user = _usersBalanceWithTwabIndex[_to];
    _usersBalanceWithTwabIndex[_to] = AmountWithTwabIndex({
      amount: (uint256(user.amount) + amount).toUint224(),
      nextTwabIndex: _newUserTwab(_to, user.nextTwabIndex),
      cardinality: CARDINALITY // maxed
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

    uint224 amount = _amount.toUint224();

    _beforeTokenTransfer(_from, address(0), _amount);

    AmountWithTwabIndex memory user = _usersBalanceWithTwabIndex[_from];
    require(user.amount >= amount, "ERC20: burn amount exceeds balance");
    unchecked {
      _usersBalanceWithTwabIndex[_from] = AmountWithTwabIndex({
        amount: user.amount - amount,
        nextTwabIndex: _newUserTwab(_from, user.nextTwabIndex),
        cardinality: CARDINALITY
      });
    }

    AmountWithTwabIndex memory ticketTotalSupply = _totalSupplyWithTwabIndex;
    _totalSupplyWithTwabIndex = AmountWithTwabIndex({
      amount: ticketTotalSupply.amount - amount,
      nextTwabIndex:  _newTotalSupplyTwab(ticketTotalSupply.nextTwabIndex),
      cardinality: CARDINALITY
    });

    emit Transfer(_from, address(0), _amount);

    _afterTokenTransfer(_from, address(0), _amount);
  }

}
