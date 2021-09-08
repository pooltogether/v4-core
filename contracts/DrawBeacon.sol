// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";

import "./interfaces/IDrawBeacon.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";
import "./prize-pool/PrizePool.sol";

contract DrawBeacon is IDrawBeacon,
                       Initializable,
                       OwnableUpgradeable {

  using SafeCastUpgradeable for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using ERC165CheckerUpgradeable for address;


  /* ============ Variables ============ */

  /// @notice RNG contract interface
  RNGInterface public rng;

  /// @notice Current RNG Request
  RngRequest internal rngRequest;

  /// @notice RNG Request Timeout.  In fact, this is really a "complete award" timeout.
  /// If the rng completes the award can still be cancelled.
  uint32 public rngRequestTimeout;

  /// @notice Seconds between draw period request
  uint256 public drawPeriodSeconds;

  /// @notice Epoch timestamp when RNG request can start
  uint256 public drawPeriodStartedAt;

  /// @notice Next draw id to use when pushing a new draw on DrawHistory
  uint32 public nextDrawId;

  /// @notice DrawHistory contract interface
  IDrawHistory public drawHistory;

  /* ============ Events ============ */

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

  /* ============ Structs ============ */

  /**
    * @notice RNG Request
    * @param id RNG request ID
    * @param lockBlock Block number that the RNG request is locked
    * @param requestedAt Epoch when RNG is requested
  */
  struct RngRequest {
    uint32 id;
    uint32 lockBlock;
    uint32 requestedAt;
  }

  /* ============ Modifiers ============ */

  modifier requireAwardNotInProgress() {
    _requireDrawNotInProgress();
    _;
  }

  modifier requireCanStartDraw() {
    require(_isDrawPeriodOver(), "DrawBeacon/prize-period-not-over");
    require(!isRngRequested(), "DrawBeacon/rng-already-requested");
    _;
  }

  modifier requireCanCompleteRngRequest() {
    require(isRngRequested(), "DrawBeacon/rng-not-requested");
    require(isRngCompleted(), "DrawBeacon/rng-not-complete");
    _;
  }

  /* ============ Initialize ============ */

  /**
    * @notice Initialize the DrawBeacon smart contract.
    * @param _rng The RNG service to use
    * @param _drawHistory The address of the draw history to push draws to
    * @param _rngRequestPeriodStart The starting timestamp of the draw period.
    * @param _drawPeriodSeconds The duration of the draw period in seconds
  */
  function initialize (
    IDrawHistory _drawHistory,
    RNGInterface _rng,
    uint256 _rngRequestPeriodStart,
    uint256 _drawPeriodSeconds
  ) public initializer {
    require(_rngRequestPeriodStart > 0, "DrawBeacon/rng-request-period-greater-than-zero");
    require(address(_rng) != address(0), "DrawBeacon/rng-not-zero");
    rng = _rng;

    __Ownable_init();

    _setDrawPeriodSeconds(_drawPeriodSeconds);
    drawPeriodStartedAt = _rngRequestPeriodStart;

    _setDrawHistory(_drawHistory);

    // 30 min timeout
    _setRngRequestTimeout(1800);

    emit Initialized(
      _drawHistory,
      _rng,
      _rngRequestPeriodStart,
      _drawPeriodSeconds
    );

    emit DrawBeaconOpened(_msgSender(), _rngRequestPeriodStart);
  }

  /* ============ Public Functions ============ */

  /**
    * @notice Returns whether the random number request has completed.
    * @return True if a random number request has completed, false otherwise.
   */
  function isRngCompleted() public view override returns (bool) {
    return rng.isRequestComplete(rngRequest.id);
  }

  /**
    * @notice Returns whether a random number has been requested
    * @return True if a random number has been requested, false otherwise.
   */
  function isRngRequested() public view override returns (bool) {
    return rngRequest.id != 0;
  }

  /**
    * @notice Returns whether the random number request has timed out.
    * @return True if a random number request has timed out, false otherwise.
   */
  function isRngTimedOut() public view override returns (bool) {
    if (rngRequest.requestedAt == 0) {
      return false;
    } else {
      return _currentTime() > uint256(rngRequestTimeout) + rngRequest.requestedAt;
    }
  }

  /* ============ External Functions ============ */

  /**
    * @notice Returns whether an award process can be started.
    * @return True if an award can be started, false otherwise.
   */
  function canStartRNGRequest() external view override returns (bool) {
    return _isDrawPeriodOver() && !isRngRequested();
  }

  /**
    * @notice Returns whether an award process can be completed.
    * @return True if an award can be completed, false otherwise.
   */
  function canCompleteRNGRequest() external view override returns (bool) {
    return isRngRequested() && isRngCompleted();
  }


  /**
    * @notice Calculates when the next draw period will start.
    * @param currentTime The timestamp to use as the current time
    * @return The timestamp at which the next draw period would start
   */
  function calculateNextDrawPeriodStartTime(uint256 currentTime) external view override returns (uint256) {
    return _calculateNextDrawPeriodStartTime(currentTime);
  }

  /**
    * @notice Can be called by anyone to cancel the RNG request if the RNG has timed out.
   */
  function cancelDraw() external override {
    require(isRngTimedOut(), "DrawBeacon/rng-not-timedout");
    uint32 requestId = rngRequest.id;
    uint32 lockBlock = rngRequest.lockBlock;
    delete rngRequest;
    emit RngRequestFailed();
    emit DrawBeaconRNGRequestCancelled(msg.sender, requestId, lockBlock);
  }

  /**
    * @notice Completes the RNG request and creates a new draw.
    * @dev    Completes the RNG request, creates a new draw on the DrawHistory and reset draw period start.
    *
   */
  function completeDraw() external override requireCanCompleteRngRequest {
    uint256 randomNumber = rng.randomNumber(rngRequest.id);
    delete rngRequest;

    _saveRNGRequestWithDraw(randomNumber);

    // to avoid clock drift, we should calculate the start time based on the previous period start time.
    drawPeriodStartedAt = _calculateNextDrawPeriodStartTime(_currentTime());

    emit DrawBeaconRNGRequestCompleted(_msgSender(), randomNumber);
    emit DrawBeaconOpened(_msgSender(), drawPeriodStartedAt);
  }

  /**
    * @notice Returns the number of seconds remaining until the rng request can be complete.
    * @return The number of seconds remaining until the rng request can be complete.
   */
  function drawPeriodRemainingSeconds() external view override returns (uint256) {
    return _drawPeriodRemainingSeconds();
  }

  /**
    * @notice Returns the timestamp at which the draw period ends
    * @return The timestamp at which the draw period ends.
   */
  function drawPeriodEndAt() external view override returns (uint256) {
    return _drawPeriodEndAt();
  }

  /**
    * @notice Estimates the remaining blocks until the prize given a number of seconds per block
    * @param secondsPerBlockMantissa The number of seconds per block to use for the calculation.  Should be a fixed point 18 number like Ether.
    * @return The estimated number of blocks remaining until the prize can be awarded.
   */
  function estimateRemainingBlocksToPrize(uint256 secondsPerBlockMantissa) external view override returns (uint256) {
    return FixedPoint.divideUintByMantissa(
      _drawPeriodRemainingSeconds(),
      secondsPerBlockMantissa
    );
  }

  /**
    * @notice Returns the block number that the current RNG request has been locked to.
    * @return The block number that the RNG request is locked to
   */
  function getLastRngLockBlock() external view override returns (uint32) {
    return rngRequest.lockBlock;
  }

  /**
    * @notice Returns the current RNG Request ID.
    * @return The current Request ID
   */
  function getLastRngRequestId() external view override returns (uint32) {
    return rngRequest.id;
  }

  /**
    * @notice Returns whether the draw period is over
    * @return True if the draw period is over, false otherwise
   */
  function isDrawPeriodOver() external view override returns (bool) {
    return _isDrawPeriodOver();
  }

  /**
    * @notice External function to set DrawHistory.
    * @dev    External function to set DrawHistory from an authorized manager.
    * @param newDrawHistory DrawHistory address
    * @return DrawHistory
  */
  function setDrawHistory(IDrawHistory newDrawHistory) external override onlyOwner returns (IDrawHistory) {
    return _setDrawHistory(newDrawHistory);
  }

  /**
    * @notice Starts the award process by starting random number request.  The draw period must have ended.
    * @dev The RNG-Request-Fee is expected to be held within this contract before calling this function
   */
  function startDraw() external override requireCanStartDraw {
    (address feeToken, uint256 requestFee) = rng.getRequestFee();
    if (feeToken != address(0) && requestFee > 0) {
      IERC20Upgradeable(feeToken).safeApprove(address(rng), requestFee);
    }

    (uint32 requestId, uint32 lockBlock) = rng.requestRandomNumber();
    rngRequest.id = requestId;
    rngRequest.lockBlock = lockBlock;
    rngRequest.requestedAt = _currentTime().toUint32();

    emit DrawBeaconRNGRequestStarted(_msgSender(), requestId, lockBlock);
  }

  /**
    * @notice Allows the owner to set the draw period in seconds.
    * @param drawPeriodSeconds The new draw period in seconds.  Must be greater than zero.
   */
  function setDrawPeriodSeconds(uint256 drawPeriodSeconds) external override onlyOwner requireAwardNotInProgress {
    _setDrawPeriodSeconds(drawPeriodSeconds);
  }
  
  /**
    * @notice Allows the owner to set the RNG request timeout in seconds. This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    * @param _rngRequestTimeout The RNG request timeout in seconds.
   */
  function setRngRequestTimeout(uint32 _rngRequestTimeout) external override onlyOwner requireAwardNotInProgress {
    _setRngRequestTimeout(_rngRequestTimeout);
  }

  /**
    * @notice Sets the RNG service that the Prize Strategy is connected to
    * @param rngService The address of the new RNG service interface
   */
  function setRngService(RNGInterface rngService) external override onlyOwner requireAwardNotInProgress {
    require(!isRngRequested(), "DrawBeacon/rng-in-flight");
    rng = rngService;
    emit RngServiceUpdated(rngService);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Calculates when the next draw period will start
    * @param currentTime The timestamp to use as the current time
    * @return The timestamp at which the next draw period would start
   */
  function _calculateNextDrawPeriodStartTime(uint256 currentTime) internal view returns (uint256) {
    uint256 _drawPeriodStartedAt = drawPeriodStartedAt; // single sload
    uint256 _drawPeriodSeconds = drawPeriodSeconds; // single sload
    uint256 elapsedPeriods = (currentTime - _drawPeriodStartedAt) / (_drawPeriodSeconds);
    return _drawPeriodStartedAt + (elapsedPeriods * _drawPeriodSeconds);
  }

  /**
    * @notice returns the current time.  Used for testing.
    * @return The current time (block.timestamp)
   */
  function _currentTime() internal virtual view returns (uint256) {
    return block.timestamp;
  }

  /**
    * @notice Returns the timestamp at which the draw period ends
    * @return The timestamp at which the draw period ends
   */
  function _drawPeriodEndAt() internal view returns (uint256) {
    return drawPeriodStartedAt + drawPeriodSeconds;
  }

  /**
    * @notice Returns the number of seconds remaining until the prize can be awarded.
    * @return The number of seconds remaining until the prize can be awarded.
   */
  function _drawPeriodRemainingSeconds() internal view returns (uint256) {
    uint256 endAt = _drawPeriodEndAt();
    uint256 time = _currentTime();
    if (time > endAt) {
      return 0;
    }
    return endAt - time;
  }

  /**
    * @notice Returns whether the draw period is over.
    * @return True if the draw period is over, false otherwise
   */
  function _isDrawPeriodOver() internal view returns (bool) {
    return _currentTime() >= _drawPeriodEndAt();
  }

  /**
    * @notice Check to see award is in progress.
   */
  function _requireDrawNotInProgress() internal view {
    uint256 currentBlock = block.number;
    require(rngRequest.lockBlock == 0 || currentBlock < rngRequest.lockBlock, "DrawBeacon/rng-in-flight");
  }

  /**
    * @notice Internal function to set DrawHistory.
    * @dev    Internal function to set DrawHistory from an authorized manager.
    * @param _newDrawHistory  DrawHistory address
    * @return DrawHistory
  */
  function _setDrawHistory(IDrawHistory _newDrawHistory) internal returns (IDrawHistory) {
    IDrawHistory _previousDrawHistory = drawHistory;
    require(address(_newDrawHistory) != address(0), "DrawBeacon/draw-history-not-zero-address");
    require(address(_newDrawHistory) != address(_previousDrawHistory), "DrawBeacon/existing-draw-history-address");
    drawHistory = _newDrawHistory;
    emit DrawHistoryTransferred(_previousDrawHistory, _newDrawHistory);
    return _newDrawHistory;
  }

  /**
    * @notice Sets the draw period in seconds.
    * @param _drawPeriodSeconds The new draw period in seconds.  Must be greater than zero.
   */
  function _setDrawPeriodSeconds(uint256 _drawPeriodSeconds) internal {
    require(_drawPeriodSeconds > 0, "DrawBeacon/rng-request-period-greater-than-zero");
    drawPeriodSeconds = _drawPeriodSeconds;

    emit RngRequestPeriodSecondsUpdated(_drawPeriodSeconds);
  }
  
  /**
    * @notice Sets the RNG request timeout in seconds.  This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    * @param _rngRequestTimeout The RNG request timeout in seconds.
   */
  function _setRngRequestTimeout(uint32 _rngRequestTimeout) internal {
    require(_rngRequestTimeout > 60, "DrawBeacon/rng-timeout-gt-60-secs");
    rngRequestTimeout = _rngRequestTimeout;
    emit RngRequestTimeoutSet(_rngRequestTimeout);
  }

  /**
    * @notice Create a new draw using the RNG request result.
    * @dev    Create a new draw in the connected DrawHistory contract using the RNG request result.
    * @param randomNumber Randomly generated number
  */
  function _saveRNGRequestWithDraw(uint256 randomNumber) internal {
    DrawLib.Draw memory _draw = DrawLib.Draw({drawId: nextDrawId, timestamp: uint32(block.timestamp), winningRandomNumber: randomNumber});
    drawHistory.pushDraw(_draw);
    nextDrawId += 1;
  }

}
