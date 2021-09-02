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

import "./Constants.sol";
import "./DrawHistory.sol";
import "./interfaces/IDrawBeacon.sol";
import "./libraries/DrawLib.sol";
import "./prize-pool/PrizePool.sol";
import "./prize-strategy/PeriodicPrizeStrategyListenerInterface.sol";
import "./prize-strategy/PeriodicPrizeStrategyListenerLibrary.sol";
import "./prize-strategy/BeforeAwardListener.sol";

abstract contract DrawBeacon is IDrawBeacon,
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

  /// @notice Seconds between RNG request
  uint256 public rngRequestPeriodSeconds;
  
  /// @notice Epoch timestamp when RNG request can start
  uint256 public rngRequestPeriodStartedAt;

  /// @notice A listener that is called before the prize is awarded
  BeforeAwardListenerInterface public beforeAwardListener;

  /// @notice A listener that is called after the prize is awarded
  PeriodicPrizeStrategyListenerInterface public drawBeaconListener;

  /// @notice Next draw id to use when pushing a new draw on DrawHistory
  uint32 public nextDrawId;

  /// @notice DrawHistory contract interface
  DrawHistory public drawHistory;

  /* ============ Events ============ */

  /**
    * @notice Emit when a new DrawHistory has been set.
    * @param previousDrawHistory  The previous DrawHistory address
    * @param newDrawHistory       The new DrawHistory address
  */
  event DrawHistoryTransferred(DrawHistory indexed previousDrawHistory, DrawHistory indexed newDrawHistory);

  /**
    * @notice Emit when a RNG request has opened.
    * @param operator              User address responsible for opening RNG request  
    * @param rngRequestPeriodStartedAt  Epoch timestamp
  */
  event DrawBeaconOpened(
    address indexed operator,
    uint256 indexed rngRequestPeriodStartedAt
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
    * @notice Emit when the rngRequestPeriodSeconds is set.
    * @param rngRequestPeriodSeconds Time between RNG request
  */
  event RngRequestPeriodSecondsUpdated(
    uint256 rngRequestPeriodSeconds
  );

  /**
    * @notice Emit when the beforeAwardListener is set.
    * @param beforeAwardListener Address of beforeAwardListener
  */
  event BeforeAwardListenerSet(
    BeforeAwardListenerInterface indexed beforeAwardListener
  );

  /**
    * @notice Emit when the drawBeaconListener is set.
    * @param drawBeaconListener Address of drawgBeaconListener
  */
  event DrawBeaconListenerSet(
    PeriodicPrizeStrategyListenerInterface indexed drawBeaconListener
  );

  /**
    * @notice Emit when the DrawBeacon is initialized.
    * @param drawHistory Address of drawHistory
    * @param rngRequestPeriodStart Timestamp when RNG request period starts
    * @param rngRequestPeriodSeconds Minimum seconds between RNG request period
    * @param rng Address of RNG service
  */
  event Initialized(
    DrawHistory indexed drawHistory,
    uint256 rngRequestPeriodStart,
    uint256 rngRequestPeriodSeconds,
    RNGInterface rng
  );

  /* ============ Structs ============ */

  /**
    * @notice Emit when the drawBeaconListener is set.
    * @param drawBeaconListener Address of drawgBeaconListener
  */
  struct RngRequest {
    uint32 id;
    uint32 lockBlock;
    uint32 requestedAt;
  }

  /* ============ Modifiers ============ */

  modifier onlyOwnerOrListener() {
    require(_msgSender() == owner() ||
            _msgSender() == address(drawBeaconListener) ||
            _msgSender() == address(beforeAwardListener),
            "DrawBeacon/only-owner-or-listener");
    _;
  }

  modifier requireAwardNotInProgress() {
    _requireRngRequestNotInProgress();
    _;
  }

  modifier requireCanStartRNGRequest() {
    require(_isRngRequestPeriodOver(), "DrawBeacon/prize-period-not-over");
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
    * @param _drawHistory DrawHistory address
    * @param _rngRequestPeriodStart The starting timestamp of the RNG request period.
    * @param _rngRequestPeriodSeconds The duration of the RNG request period in seconds
    * @param _rng The RNG service to use
  */
  function initialize (
    DrawHistory _drawHistory,
    uint256 _rngRequestPeriodStart,
    uint256 _rngRequestPeriodSeconds,
    RNGInterface _rng
  ) public initializer {
    require(address(_rng) != address(0), "DrawBeacon/rng-not-zero");
    rng = _rng;
    _setDrawHistory(_drawHistory);

    __Ownable_init();
    Constants.REGISTRY.setInterfaceImplementer(address(this), Constants.TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

    _setRngRequestPeriodSeconds(_rngRequestPeriodSeconds);
    rngRequestPeriodStartedAt = _rngRequestPeriodStart;
    

    // 30 min timeout
    _setRngRequestTimeout(1800);

    emit Initialized(
      _drawHistory,
      _rngRequestPeriodStart,
      _rngRequestPeriodSeconds,
      _rng
    );
    
    emit DrawBeaconOpened(_msgSender(), _rngRequestPeriodStart);
  }

  /* ============ Public Functions ============ */

  /**
    * @notice Estimates the remaining blocks until the prize given a number of seconds per block
    * @param secondsPerBlockMantissa The number of seconds per block to use for the calculation.  Should be a fixed point 18 number like Ether.
    * @return The estimated number of blocks remaining until the prize can be awarded.
   */
  function estimateRemainingBlocksToPrize(uint256 secondsPerBlockMantissa) public view returns (uint256) {
    return FixedPoint.divideUintByMantissa(
      _rngRequestPeriodRemainingSeconds(),
      secondsPerBlockMantissa
    );
  }

  /**
    * @notice Can be called by anyone to cancel the RNG request if the RNG has timed out.
   */
  function cancelRngRequest() public {
    require(isRngTimedOut(), "DrawBeacon/rng-not-timedout");
    uint32 requestId = rngRequest.id;
    uint32 lockBlock = rngRequest.lockBlock;
    delete rngRequest;
    emit RngRequestFailed();
    emit DrawBeaconRNGRequestCancelled(msg.sender, requestId, lockBlock);
  }

  /**
    * @notice Returns whether a random number has been requested
    * @return True if a random number has been requested, false otherwise.
   */
  function isRngRequested() public view returns (bool) {
    return rngRequest.id != 0;
  }

  /**
    * @notice Returns whether the random number request has completed.
    * @return True if a random number request has completed, false otherwise.
   */
  function isRngCompleted() public view returns (bool) {
    return rng.isRequestComplete(rngRequest.id);
  }

  /**
    * @notice Returns whether the random number request has timed out.
    * @return True if a random number request has timed out, false otherwise.
   */
  function isRngTimedOut() public view returns (bool) {
    if (rngRequest.requestedAt == 0) {
      return false;
    } else {
      return _currentTime() > uint256(rngRequestTimeout) + rngRequest.requestedAt;
    }
  }

  /* ============ External Functions ============ */

  /**
    * @notice External function to set DrawHistory.
    * @dev    External function to set DrawHistory from an authorized manager.
    * @param newDrawHistory  DrawHistory address
    * @return DrawHistory
  */
  function setDrawHistory(DrawHistory newDrawHistory) external override onlyOwner returns (DrawHistory) {
    return _setDrawHistory(newDrawHistory);
  }

  /**
    * @notice Returns the number of seconds remaining until the rng request can be complete.
    * @return The number of seconds remaining until the rng request can be complete.
   */
  function rngRequestPeriodRemainingSeconds() external view returns (uint256) {
    return _rngRequestPeriodRemainingSeconds();
  }

  /**
    * @notice Returns whether the RNG request period is over
    * @return True if the RNG request period is over, false otherwise
   */
  function isRngRequestPeriodOver() external view returns (bool) {
    return _isRngRequestPeriodOver();
  }

  /**
    * @notice Returns the timestamp at which the RNG request period ends
    * @return The timestamp at which the RNG request period ends.
   */
  function rngRequestPeriodEndAt() external view returns (uint256) {
    return _rngRequestPeriodEndAt();
  }

  /**
    * @notice Starts the award process by starting random number request.  The RNG request period must have ended.
    * @dev The RNG-Request-Fee is expected to be held within this contract before calling this function
   */
  function startRNGRequest() external requireCanStartRNGRequest {
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
    * @notice Completes the RNG request and creates a new draw.
    * @dev    Completes the RNG request, creates a new draw on the DrawHistory and reset RNG request period start.
    *
   */
  function completeRNGRequest() external requireCanCompleteRngRequest {
    uint256 randomNumber = rng.randomNumber(rngRequest.id);
    delete rngRequest;

    if (address(beforeAwardListener) != address(0)) {
      beforeAwardListener.beforePrizePoolAwarded(randomNumber, rngRequestPeriodStartedAt);
    }
    _saveRNGRequestWithDraw(randomNumber);
    if (address(drawBeaconListener) != address(0)) {
      drawBeaconListener.afterPrizePoolAwarded(randomNumber, rngRequestPeriodStartedAt);
    }

    // to avoid clock drift, we should calculate the start time based on the previous period start time.
    rngRequestPeriodStartedAt = _calculateNextRngRequestPeriodStartTime(_currentTime());

    emit DrawBeaconRNGRequestCompleted(_msgSender(), randomNumber);
    emit DrawBeaconOpened(_msgSender(), rngRequestPeriodStartedAt);
  }

  /**
    * @notice Allows the owner to set a listener that is triggered immediately before the award is distributed
    * @dev The listener must implement ERC165 and the BeforeAwardListenerInterface
    * @param _beforeAwardListener The address of the listener contract
   */
  function setBeforeAwardListener(BeforeAwardListenerInterface _beforeAwardListener) external onlyOwner requireAwardNotInProgress {
    require(
      address(0) == address(_beforeAwardListener) || address(_beforeAwardListener).supportsInterface(BeforeAwardListenerLibrary.ERC165_INTERFACE_ID_BEFORE_AWARD_LISTENER),
      "DrawBeacon/beforeAwardListener-invalid"
    );

    beforeAwardListener = _beforeAwardListener;

    emit BeforeAwardListenerSet(_beforeAwardListener);
  }

  /**
    * @notice Allows the owner to set a listener for prize strategy callbacks.
    * @param _drawBeaconListener The address of the listener contract
   */
  function setDrawBeaconListener(PeriodicPrizeStrategyListenerInterface _drawBeaconListener) external onlyOwner requireAwardNotInProgress {
    require(
      address(0) == address(_drawBeaconListener) || address(_drawBeaconListener).supportsInterface(PeriodicPrizeStrategyListenerLibrary.ERC165_INTERFACE_ID_PERIODIC_PRIZE_STRATEGY_LISTENER),
      "DrawBeacon/drawBeaconListener-invalid"
    );

    drawBeaconListener = _drawBeaconListener;

    emit DrawBeaconListenerSet(_drawBeaconListener);
  }

  /**
    * @notice Calculates when the next RNG request period will start.
    * @param currentTime The timestamp to use as the current time
    * @return The timestamp at which the next RNG request period would start
   */
  function calculateNextRngRequestPeriodStartTime(uint256 currentTime) external view returns (uint256) {
    return _calculateNextRngRequestPeriodStartTime(currentTime);
  }

  /**
    * @notice Returns whether an award process can be started.
    * @return True if an award can be started, false otherwise.
   */
  function canStartRNGRequest() external view returns (bool) {
    return _isRngRequestPeriodOver() && !isRngRequested();
  }

  /**
    * @notice Returns whether an award process can be completed.
    * @return True if an award can be completed, false otherwise.
   */
  function canCompleteRNGRequest() external view returns (bool) {
    return isRngRequested() && isRngCompleted();
  }

  /**
    * @notice Returns the block number that the current RNG request has been locked to.
    * @return The block number that the RNG request is locked to
   */
  function getLastRngLockBlock() external view returns (uint32) {
    return rngRequest.lockBlock;
  }

  /**
    * @notice Returns the current RNG Request ID.
    * @return The current Request ID
   */
  function getLastRngRequestId() external view returns (uint32) {
    return rngRequest.id;
  }

  /**
    * @notice Sets the RNG service that the Prize Strategy is connected to
    * @param rngService The address of the new RNG service interface
   */
  function setRngService(RNGInterface rngService) external onlyOwner requireAwardNotInProgress {
    require(!isRngRequested(), "DrawBeacon/rng-in-flight");
    rng = rngService;
    emit RngServiceUpdated(rngService);
  }

  /**
    * @notice Allows the owner to set the RNG request timeout in seconds. This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    * @param _rngRequestTimeout The RNG request timeout in seconds.
   */
  function setRngRequestTimeout(uint32 _rngRequestTimeout) external onlyOwner requireAwardNotInProgress {
    _setRngRequestTimeout(_rngRequestTimeout);
  }

  /**
    * @notice Allows the owner to set the RNG request period in seconds.
    * @param rngRequestPeriodSeconds The new RNG request period in seconds.  Must be greater than zero.
   */
  function setRngRequestPeriodSeconds(uint256 rngRequestPeriodSeconds) external onlyOwner requireAwardNotInProgress {
    _setRngRequestPeriodSeconds(rngRequestPeriodSeconds);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Calculates when the next RNG request period will start
    * @param currentTime The timestamp to use as the current time
    * @return The timestamp at which the next RNG request period would start
   */
  function _calculateNextRngRequestPeriodStartTime(uint256 currentTime) internal view returns (uint256) {
    uint256 _rngRequestPeriodStartedAt = rngRequestPeriodStartedAt; // single sload
    uint256 _rngRequestPeriodSeconds = rngRequestPeriodSeconds; // single sload
    uint256 elapsedPeriods = (currentTime - _rngRequestPeriodStartedAt) / (_rngRequestPeriodSeconds);
    return _rngRequestPeriodStartedAt + (elapsedPeriods * _rngRequestPeriodSeconds);
  }

  /**
    * @notice Returns whether the RNG request period is over.
    * @return True if the RNG request period is over, false otherwise
   */
  function _isRngRequestPeriodOver() internal view returns (bool) {
    return _currentTime() >= _rngRequestPeriodEndAt();
  }

  /**
    * @notice Returns the timestamp at which the RNG request period ends
    * @return The timestamp at which the RNG request period ends
   */
  function _rngRequestPeriodEndAt() internal view returns (uint256) {
    return rngRequestPeriodStartedAt + rngRequestPeriodSeconds;
  }

  /**
    * @notice Returns the number of seconds remaining until the prize can be awarded.
    * @return The number of seconds remaining until the prize can be awarded.
   */
  function _rngRequestPeriodRemainingSeconds() internal view returns (uint256) {
    uint256 endAt = _rngRequestPeriodEndAt();
    uint256 time = _currentTime();
    if (time > endAt) {
      return 0;
    }
    return endAt - time;
  }

  /**
    * @notice Check to see award is in progress.
   */
  function _requireRngRequestNotInProgress() internal view {
    uint256 currentBlock = block.number;
    require(rngRequest.lockBlock == 0 || currentBlock < rngRequest.lockBlock, "DrawBeacon/rng-in-flight");
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

  /**
    * @notice Internal function to set DrawHistory.
    * @dev    Internal function to set DrawHistory from an authorized manager.
    * @param _newDrawHistory  DrawHistory address
    * @return DrawHistory
  */
  function _setDrawHistory(DrawHistory _newDrawHistory) internal returns (DrawHistory) {
    DrawHistory _previousDrawHistory = drawHistory;
    require(address(_newDrawHistory) != address(0), "DrawBeacon/draw-history-not-zero-address");
    require(address(_newDrawHistory) != address(_previousDrawHistory), "DrawBeacon/existing-draw-history-address");
    drawHistory = _newDrawHistory;
    emit DrawHistoryTransferred(_previousDrawHistory, _newDrawHistory);
    return _newDrawHistory;
  }

  /**
    * @notice Sets the RNG request period in seconds.
    * @param _rngRequestPeriodSeconds The new RNG request period in seconds.  Must be greater than zero.
   */
  function _setRngRequestPeriodSeconds(uint256 _rngRequestPeriodSeconds) internal {
    require(_rngRequestPeriodSeconds > 0, "DrawBeacon/rng-request-period-greater-than-zero");
    rngRequestPeriodSeconds = _rngRequestPeriodSeconds;

    emit RngRequestPeriodSecondsUpdated(_rngRequestPeriodSeconds);
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
    * @notice returns the current time.  Used for testing.
    * @return The current time (block.timestamp)
   */
  function _currentTime() internal virtual view returns (uint256) {
    return block.timestamp;
  }

}
