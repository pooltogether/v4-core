// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";
import "./IDrawHistory.sol";
import "../libraries/DrawLib.sol";

interface IDrawBeacon {

  /**
    * @notice Emit when the DrawBeacon is initialized.
    * @param drawHistory Address of the draw history to push draws to
    * @param rng Address of RNG service
    * @param rngRequestPeriodStart Timestamp when draw period starts
    * @param drawPeriodSeconds Minimum seconds between draw period
  */
  event Initialized(
    IDrawHistory indexed drawHistory,
    RNGInterface indexed rng,
    uint256 rngRequestPeriodStart,
    uint256 drawPeriodSeconds
  );

  /**
    * @notice Emit when a new DrawHistory has been set.
    * @param previousDrawHistory  The previous DrawHistory address
    * @param newDrawHistory       The new DrawHistory address
  */
  event DrawHistoryTransferred(IDrawHistory indexed previousDrawHistory, IDrawHistory indexed newDrawHistory);

  /**
    * @notice Emit when a RNG request has opened.
    * @param operator              User address responsible for opening RNG request  
    * @param drawPeriodStartedAt  Epoch timestamp
  */
  event DrawBeaconOpened(
    address indexed operator,
    uint256 indexed drawPeriodStartedAt
  );

  /**
    * @notice Emit when a RNG request has started.
    * @param operator      User address responsible for starting RNG request  
    * @param rngRequestId  RNG request id
    * @param rngLockBlock  Block when RNG request becomes invalid
  */
  event DrawBeaconRNGRequestStarted(
    address indexed operator,
    uint32 indexed rngRequestId,
    uint32 rngLockBlock
  );

  /**
    * @notice Emit when a RNG request has been cancelled.
    * @param operator      User address responsible for cancelling RNG request  
    * @param rngRequestId  RNG request id
    * @param rngLockBlock  Block when RNG request becomes invalid
  */
  event DrawBeaconRNGRequestCancelled(
    address indexed operator,
    uint32 indexed rngRequestId,
    uint32 rngLockBlock
  );
  
  /**
    * @notice Emit when a RNG request has been completed.
    * @param operator      User address responsible for completing RNG request  
    * @param randomNumber  Random number generated from RNG request
  */
  event DrawBeaconRNGRequestCompleted(
    address indexed operator,
    uint256 randomNumber
  );

  /**
    * @notice Emit when a RNG request has failed.
  */
  event RngRequestFailed();

  /**
    * @notice Emit when a RNG service address is set.
    * @param rngService  RNG service address
  */
  event RngServiceUpdated(
    RNGInterface indexed rngService
  );

  /**
    * @notice Emit when a RNG request timeout param is set.
    * @param rngRequestTimeout  RNG request timeout param in seconds
  */
  event RngRequestTimeoutSet(
    uint32 rngRequestTimeout
  );

  /**
    * @notice Emit when the drawPeriodSeconds is set.
    * @param drawPeriodSeconds Time between RNG request
  */
  event RngRequestPeriodSecondsUpdated(
    uint256 drawPeriodSeconds
  );

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