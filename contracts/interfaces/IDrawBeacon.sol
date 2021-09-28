// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";
import "./IDrawHistory.sol";
import "../libraries/DrawLib.sol";

interface IDrawBeacon {

  /**
    * @notice Emit when a new DrawHistory has been set.
    * @param previousDrawHistory  The previous DrawHistory address
    * @param newDrawHistory       The new DrawHistory address
  */
  event DrawHistoryTransferred(IDrawHistory indexed previousDrawHistory, IDrawHistory indexed newDrawHistory);

  /**
    * @notice Emit when a draw has opened.
    * @param operator             User address responsible for opening draw
    * @param startedAt Start timestamp
  */
  event BeaconPeriodStarted(
    address indexed operator,
    uint64 indexed startedAt
  );

  /**
    * @notice Emit when a draw has started.
    * @param operator      User address responsible for starting draw
    * @param rngRequestId  draw id
    * @param rngLockBlock  Block when draw becomes invalid
  */
  event DrawStarted(
    address indexed operator,
    uint32 indexed rngRequestId,
    uint32 rngLockBlock
  );

  /**
    * @notice Emit when a draw has been cancelled.
    * @param operator      User address responsible for cancelling draw
    * @param rngRequestId  draw id
    * @param rngLockBlock  Block when draw becomes invalid
  */
  event DrawCancelled(
    address indexed operator,
    uint32 indexed rngRequestId,
    uint32 rngLockBlock
  );

  /**
    * @notice Emit when a draw has been completed.
    * @param operator      User address responsible for completing draw
    * @param randomNumber  Random number generated from draw
  */
  event DrawCompleted(
    address indexed operator,
    uint256 randomNumber
  );

  /**
    * @notice Emit when a RNG service address is set.
    * @param rngService  RNG service address
  */
  event RngServiceUpdated(
    RNGInterface indexed rngService
  );

  /**
    * @notice Emit when a draw timeout param is set.
    * @param rngTimeout  draw timeout param in seconds
  */
  event RngTimeoutSet(
    uint32 rngTimeout
  );

  /**
    * @notice Emit when the drawPeriodSeconds is set.
    * @param drawPeriodSeconds Time between draw
  */
  event BeaconPeriodSecondsUpdated(
    uint32 drawPeriodSeconds
  );

  /**
    * @notice Returns the number of seconds remaining until the beacon period can be complete.
    * @return The number of seconds remaining until the beacon period can be complete.
   */
  function beaconPeriodRemainingSeconds() external view returns (uint32);

  /**
    * @notice Returns the timestamp at which the beacon period ends
    * @return The timestamp at which the beacon period ends.
   */
  function beaconPeriodEndAt() external view returns (uint64);


  /**
    * @notice Returns whether an Draw request can be started.
    * @return True if a Draw can be started, false otherwise.
   */
  function canStartDraw() external view returns (bool);
  
  /**
    * @notice Returns whether an Draw request can be completed.
    * @return True if a Draw can be completed, false otherwise.
   */
  function canCompleteDraw() external view returns (bool);
  
  /**
    * @notice Calculates when the next beacon period will start.
    * @param currentTime The timestamp to use as the current time
    * @return The timestamp at which the next beacon period would start
   */
  function calculateNextBeaconPeriodStartTime(uint256 currentTime) external view returns (uint64);
  
  /**
    * @notice Can be called by anyone to cancel the draw request if the RNG has timed out.
   */
  function cancelDraw() external;

  /**
    * @notice Completes the Draw (RNG) request and pushes a Draw onto DrawHistory.
   */
  function completeDraw() external;
  
  /**
    * @notice Returns the block number that the current RNG request has been locked to.
    * @return The block number that the RNG request is locked to
   */
  function getLastRngLockBlock() external view returns (uint32);
  /**
    * @notice Returns the current RNG Request ID.
    * @return The current Request ID
   */
  function getLastRngRequestId() external view returns (uint32);
  /**
    * @notice Returns whether the beacon period is over
    * @return True if the beacon period is over, false otherwise
   */
  function isBeaconPeriodOver() external view returns (bool);

  /**
    * @notice Returns whether the random number request has completed.
    * @return True if a random number request has completed, false otherwise.
   */
  function isRngCompleted() external view returns (bool);

  /**
    * @notice Returns whether a random number has been requested
    * @return True if a random number has been requested, false otherwise.
   */
  function isRngRequested() external view returns (bool);

  /**
    * @notice Returns whether the random number request has timed out.
    * @return True if a random number request has timed out, false otherwise.
   */
  function isRngTimedOut() external view returns (bool);
  /**
    * @notice Allows the owner to set the beacon period in seconds.
    * @param beaconPeriodSeconds The new beacon period in seconds.  Must be greater than zero.
   */
  function setBeaconPeriodSeconds(uint32 beaconPeriodSeconds) external;
  /**
    * @notice Allows the owner to set the RNG request timeout in seconds. This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    * @param _rngTimeout The RNG request timeout in seconds.
   */
  function setRngTimeout(uint32 _rngTimeout) external;
  /**
    * @notice Sets the RNG service that the Prize Strategy is connected to
    * @param rngService The address of the new RNG service interface
   */
  function setRngService(RNGInterface rngService) external;
  /**
    * @notice Starts the Draw process by starting random number request. The previous beacon period must have ended.
    * @dev The RNG-Request-Fee is expected to be held within this contract before calling this function
   */
  function startDraw() external;
  /**
    * @notice Set global DrawHistory variable.
    * @dev    All subsequent Draw requests/completions will be pushed to the new DrawHistory.
    * @param newDrawHistory DrawHistory address
    * @return DrawHistory
  */
  function setDrawHistory(IDrawHistory newDrawHistory) external returns (IDrawHistory);
}
