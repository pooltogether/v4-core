// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";
import "./IDrawHistory.sol";
import "../libraries/DrawLib.sol";

interface IDrawBeacon {
  function canStartRNGRequest() external view virtual returns (bool);
  function canCompleteRNGRequest() external view virtual returns (bool);
  function calculateNextDrawPeriodStartTime(uint256 currentTime) external view virtual returns (uint256);
  function cancelDraw() external virtual;
  function completeDraw() external virtual;
  function drawPeriodRemainingSeconds() external view virtual returns (uint256);
  function drawPeriodEndAt() external view virtual returns (uint256);
  function estimateRemainingBlocksToPrize(uint256 secondsPerBlockMantissa) external view virtual returns (uint256);
  function getLastRngLockBlock() external view returns (uint32);
  function getLastRngRequestId() external view returns (uint32);
  function isDrawPeriodOver() external view returns (bool);
  function isRngCompleted() external view returns (bool);
  function isRngRequested() external view returns (bool);
  function isRngTimedOut() external view returns (bool);
  function setDrawPeriodSeconds(uint256 drawPeriodSeconds) external;
  function setRngRequestTimeout(uint32 _rngRequestTimeout) external;
  function setRngService(RNGInterface rngService) external;
  function startDraw() external virtual;
  function setDrawHistory(IDrawHistory newDrawHistory) external virtual returns (IDrawHistory);
}