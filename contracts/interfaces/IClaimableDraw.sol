// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./IDrawHistory.sol";
import "./IDrawCalculator.sol";
import "../libraries/DrawLib.sol";

interface IClaimableDraw {
  
  /**
    * @notice Emitted when a user has claimed N draw payouts.
    * @param user        User address receiving draw claim payouts
    * @param totalPayout Payout for N draw claims 
  */
  event ClaimedDraw (
    address indexed user,
    uint256 totalPayout
  );

  /**
    * @notice Emitted when a DrawCalculator is linked to a Draw ID.
    * @param drawId     Draw ID
    * @param calculator DrawCalculator address
  */
  event DrawCalculatorSet (
    uint256 drawId,
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
    * @notice Emitted when ERC20 tokens are withdrawn from the claimable draw.
    * @param token ERC20 token transferred.
    * @param to Address that received funds.
    * @param amount Amount of tokens transferred.
  */
  event ERC20Withdrawn(
    IERC20Upgradeable indexed token,
    address indexed to,
    uint256 amount
  );

  function claim(address _user, uint32[][] calldata _drawIds, IDrawCalculator[] calldata _drawCalculators, bytes[] calldata _data) external returns (uint256);
  function getCardinality() external view returns (uint16);
  function getDrawCalculator(uint32 drawId) external view returns (IDrawCalculator);
  function getDrawCalculators(uint32[] calldata drawIds) external view returns (IDrawCalculator[] memory);
  function getDrawHistory() external view returns (IDrawHistory);
  function getTicket() external view returns (IERC20Upgradeable);
  function getUserDrawClaim(address user, uint32 drawId) external view returns (uint96);
  function getUserDrawClaims(address user) external view returns(uint96[8] memory);
  function setDrawCalculator(uint32 _drawId, IDrawCalculator _newCalculator) external returns(IDrawCalculator);
  function setDrawHistory(IDrawHistory _drawHistory) external returns (IDrawHistory);
  function withdrawERC20(IERC20Upgradeable _erc20Token, address _to, uint256 _amount) external returns (bool); 
}