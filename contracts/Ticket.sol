// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./TicketTwab.sol";

/// @title Ticket contract inerhiting from ERC20 and updated to keep track of users balance.
/// @author PoolTogether Inc.
contract Ticket is TicketTwab, ERC20PermitUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using OverflowSafeComparator for uint32;
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

  /// @notice Returns the ERC20 ticket token balance of a ticket holder.
  /// @return uint240 `_user` ticket token balance.
  function balanceOf(address _user) public view override returns (uint256) {
    return _balancesWithTwabIndex[_user].balance;
  }

  /// @notice Returns the ERC20 ticket token total supply.
  /// @return uint256 Total supply of the ERC20 ticket token.
  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
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
          nextTwabIndex: _newTwab(_sender, sender.nextTwabIndex)
        });
    }

    BalanceWithTwabIndex memory recipient = _balancesWithTwabIndex[_recipient];
    _balancesWithTwabIndex[_recipient] = BalanceWithTwabIndex({
      balance: recipient.balance + uint240(_amount),
      nextTwabIndex: _newTwab(_recipient, recipient.nextTwabIndex)
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
      nextTwabIndex: _newTwab(_to, user.nextTwabIndex)
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
        nextTwabIndex: _newTwab(_from, user.nextTwabIndex)
      });
    }

    _totalSupply -= _amount;

    emit Transfer(_from, address(0), _amount);

    _afterTokenTransfer(_from, address(0), _amount);
  }

}
