// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IDrawHistory.sol";
import "./IDrawCalculator.sol";
import "../libraries/DrawLib.sol";

interface IClaimableDraw {

  /**
    * @notice Emitted when a user has claimed N draw payouts.
    * @param user        User address receiving draw claim payouts
    * @param drawId      Draw id that was paid out
    * @param payout Payout for draw
  */
  event ClaimedDraw (
    address indexed user,
    uint32 indexed drawId,
    uint256 payout
  );

  /**
    * @notice Emitted when a DrawCalculator is set
    * @param calculator DrawCalculator address
  */
  event DrawCalculatorSet (
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emitted when a global DrawHistory variable is set.
    * @param drawHistory DrawHistory address
  */
  event DrawHistorySet (
    IDrawHistory indexed drawHistory
  );

  /**
    * @notice Emitted when a global Ticket variable is set.
    * @param token Token address
  */
  event TokenSet (
    IERC20 indexed token
  );

  /**
    * @notice Emitted when ERC20 tokens are withdrawn from the claimable draw.
    * @param token ERC20 token transferred.
    * @param to Address that received funds.
    * @param amount Amount of tokens transferred.
  */
  event ERC20Withdrawn(
    IERC20 indexed token,
    address indexed to,
    uint256 amount
  );

  function claim(address _user, uint32[] calldata _drawIds, bytes calldata _data) external returns (uint256);
  function getDrawCalculator() external view returns (IDrawCalculator);
  function getDrawHistory() external view returns (IDrawHistory);
  function getDrawPayoutBalanceOf(address user, uint32 drawId) external view returns (uint256);
  function getToken() external view returns (IERC20);
  function setDrawCalculator(IDrawCalculator _newCalculator) external returns(IDrawCalculator);
  function setDrawHistory(IDrawHistory _drawHistory) external returns (IDrawHistory);
  function withdrawERC20(IERC20 _erc20Token, address _to, uint256 _amount) external returns (bool);
}
