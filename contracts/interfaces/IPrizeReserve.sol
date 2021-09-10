// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../libraries/TwabLibrary.sol";
import "./IControlledToken.sol";
import "./IPrizePool.sol";

interface IPrizeReserve {
  /// @dev Emitted when an instance is created
  event Created(
    IControlledToken sponsorshipToken
  );

  /// @notice Emitted when a new balance TWAB has been recorded.
  /// @param newTwab Updated balance TWAB after a successful TWAB recording.
  event NewBalanceTwab(
    TwabLibrary.Twab newTwab
  );

  /// @notice Emitted when a new withdrawal TWAB has been recorded.
  /// @param newTwab Updated withdrawal TWAB after a successful TWAB recording.
  event NewWithdrawalTwab(
    TwabLibrary.Twab newTwab
  );

  /// @dev Event emitted when tokens are withdrawn from the prize reserve.
  event Withdrawn(
    address indexed sender,
    address indexed recipient,
    uint256 amount
  );

  /// @notice Records internaly the cummulated amount of tokens held by the prize reserve.
  /// @dev This function is callable by anyone.
  /// @return A boolean indicating success.
  function checkpoint() external returns (bool);

  /// @notice Get current reserve balance.
  /// @return Current reserve balance.
  function getBalance() external view returns (uint256);

  /// @notice Get reserve balance at `target`.
  /// @param target Timestamp to get balance at.
  /// @return Balance at `target`.
  function getBalanceAt(uint256 target) external view returns (uint256);

  /// @notice Withdraw tokens from the prize reserve.
  /// @dev This function is only callable by the owner.
  /// @param to Address to send tokens `to`.
  /// @param amount Requested `amount` to withdraw.
  /// @return A boolean indicating success.
  function withdraw(address to, uint256 amount) external returns (bool);
}
