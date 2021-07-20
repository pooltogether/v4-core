// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/draft-ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./interfaces/ITicket.sol";

contract Ticket is ITicket, ERC20PermitUpgradeable, OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
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

  struct Balance {
    uint224 balance;
    uint32 timestamp;
  }

  /// @notice Record of token balances for each account
  mapping (address => Balance[32]) internal balances;

  /// @notice
  mapping (address => uint256) internal balanceIndices;

  // struct RingBuffer {
  //   Twab[65535] balances;
  // }

  // mapping(address => RingBuffer) internal twabs;

  /// @notice Initializes Ticket with passed parameters.
  /// @param _name Ticket's EIP-20 token name.
  /// @param _symbol Ticket's EIP-20 token symbol.
  /// @param _decimals Ticket's EIP-20 token decimals.
  function initialize (
    string calldata _name,
    string calldata _symbol,
    uint8 _decimals
  ) public initializer {
    // name = _name;
    // symbol = _symbol;

    // __ERC20_init(_name, _symbol);
    // __ERC20Permit_init("PoolTogether Ticket");

    require(_decimals > 0, "Ticket/decimals-gt-zero");
    // _setupDecimals(_decimals);

    emit TicketInitialized(_name, _symbol, _decimals);
  }

  // @notice Get the number of tokens held by the `account`
  // @param account Address of the account to get the balance of
  // @return Number of tokens held
  // function balanceOf(address account) external view override returns (uint256) {
  //     return balances[account];
  // }

  /* ============ External Functions ============ */

  function updateBalance(address user, uint256 balance, uint256 currentDrawNumber) external {

  }

  function setRandomNumber(bytes32 randomNumber, uint256 currentDrawNumber) external {

  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    if (from != address(0)) {
      uint256 _balanceIndicesFrom = balanceIndices[from];

      balances[from][_balanceIndicesFrom] = Balance ({
        balance: uint224(balanceOf(from) - amount),
        timestamp: uint32(block.timestamp)
      });

      balanceIndices[from] = _balanceIndicesFrom + 1;
    }

    if (to != address(0)) {
      uint256 _balanceIndicesTo = balanceIndices[to];

      balances[to][_balanceIndicesTo] = Balance ({
        balance: uint224(balanceOf(to) + amount),
        timestamp: uint32(block.timestamp)
      });

      balanceIndices[to] = _balanceIndicesTo + 1;
    }
  }

  function getBalance(address user, uint32 timestamp) external view returns (uint256) {
    uint256 nBalances = balances[user].length;
    uint256 lower = 0;
    uint256 upper = nBalances - 1;

    Balance memory balance;

    while (upper >= lower) {
        uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
        balance = balances[user][center];

        if ((lower == upper) || (balance.timestamp == timestamp)) {
            break;
        } else if (balance.timestamp < timestamp) {
            lower = center;
        } else {
            upper = center - 1;
        }
    }

    return balance.balance;
  }

  function getRandonNumber(address user, uint256 drawNumber) external view returns (bytes32) {

  }

  /* ============ Internal Functions ============ */


}
