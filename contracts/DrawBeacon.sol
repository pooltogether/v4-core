// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";
import "@pooltogether/owner-manager-contracts/contracts/Ownable.sol";
import "./interfaces/IDrawBeacon.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";

/**
  * @title  PoolTogether V4 DrawBeacon
  * @author PoolTogether Inc Team
  * @notice Manages RNG (random number generator) requests and pushing Draws onto DrawHistory.
            The DrawBeacon has 3 major phases for requesting a random number: start, cancel and complete.
            Once the complete phase is executed a new Draw (using nextDrawId) is pushed to the currently
            set DrawHistory smart contracts. If the RNG service requires payment (i.e. ChainLink) the DrawBeacon
            should have an available balance to cover the fees associated with random number generation.
*/
contract DrawBeacon is IDrawBeacon,
                       Ownable {

  using SafeCast for uint256;
  using SafeERC20 for IERC20;
  using Address for address;
  using ERC165Checker for address;

  /* ============ Variables ============ */

  /// @notice RNG contract interface
  RNGInterface public rng;

  /// @notice Current RNG Request
  RngRequest internal rngRequest;

  /// @notice DrawHistory address
  IDrawHistory public drawHistory;

  /**
    * @notice RNG Request Timeout.  In fact, this is really a "complete draw" timeout.
    * @dev If the rng completes the award can still be cancelled.
   */
  uint32 public rngTimeout;
  // first four words of mem end here

  /// @notice Seconds between beacon period request
  uint32 public beaconPeriodSeconds;

  /// @notice Epoch timestamp when beacon period can start
  uint64 public beaconPeriodStartedAt;

  /**
    * @notice Next Draw ID to use when pushing a Draw onto DrawHistory
    * @dev Starts at 1. This way we know that no Draw has been recorded at 0.
  */
  uint32 public nextDrawId;

  /* ============ Structs ============ */

  /**
    * @notice RNG Request
    * @param id          RNG request ID
    * @param lockBlock   Block number that the RNG request is locked
    * @param requestedAt Time when RNG is requested
  */
  struct RngRequest {
    uint32 id;
    uint32 lockBlock;
    uint64 requestedAt;
  }

  /* ============ Evens ============ */

  /**
    * @notice Emit when the DrawBeacon is initialized.
    * @param drawHistory Address of the draw history to push draws to.
    * @param rng Address of RNG service.
    * @param nextDrawId Draw ID at which the DrawBeacon should start. Can't be inferior to 1.
    * @param beaconPeriodStartedAt Timestamp when beacon period starts.
    * @param beaconPeriodSeconds Minimum seconds between draw period.
  */
  event Deployed(
    IDrawHistory indexed drawHistory,
    RNGInterface indexed rng,
    uint32 nextDrawId,
    uint64 beaconPeriodStartedAt,
    uint32 beaconPeriodSeconds
  );

  /* ============ Modifiers ============ */

  modifier requireDrawNotInProgress() {
    _requireDrawNotInProgress();
    _;
  }

  modifier requireCanStartDraw() {
    require(_isBeaconPeriodOver(), "DrawBeacon/beacon-period-not-over");
    require(!isRngRequested(), "DrawBeacon/rng-already-requested");
    _;
  }

  modifier requireCanCompleteRngRequest() {
    require(isRngRequested(), "DrawBeacon/rng-not-requested");
    require(isRngCompleted(), "DrawBeacon/rng-not-complete");
    _;
  }

  /* ============ Constructor ============ */

  /**
    * @notice Deploy the DrawBeacon smart contract.
    * @param _owner Address of the DrawBeacon owner
    * @param _drawHistory The address of the draw history to push draws to
    * @param _rng The RNG service to use
    * @param _nextDrawId Draw ID at which the DrawBeacon should start. Can't be inferior to 1.
    * @param _beaconPeriodStart The starting timestamp of the beacon period.
    * @param _beaconPeriodSeconds The duration of the beacon period in seconds
  */
  constructor (
    address _owner,
    IDrawHistory _drawHistory,
    RNGInterface _rng,
    uint32 _nextDrawId,
    uint64 _beaconPeriodStart,
    uint32 _beaconPeriodSeconds
  ) Ownable(_owner) {
    require(_beaconPeriodStart > 0, "DrawBeacon/beacon-period-greater-than-zero");
    require(address(_rng) != address(0), "DrawBeacon/rng-not-zero");
    rng = _rng;

    _setBeaconPeriodSeconds(_beaconPeriodSeconds);
    beaconPeriodStartedAt = _beaconPeriodStart;

    _setDrawHistory(_drawHistory);

    // 30 min timeout
    _setRngTimeout(1800);

    require(_nextDrawId >= 1, "DrawBeacon/next-draw-id-gte-one");
    nextDrawId = _nextDrawId;

    emit Deployed(
      _drawHistory,
      _rng,
      _nextDrawId,
      _beaconPeriodStart,
      _beaconPeriodSeconds
    );

    emit BeaconPeriodStarted(msg.sender, _beaconPeriodStart);
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
      uint64 time = _currentTime();
      return rngTimeout + rngRequest.requestedAt < time;
    }
  }

  /* ============ External Functions ============ */

  /// @inheritdoc IDrawBeacon
  function canStartDraw() external view override returns (bool) {
    return _isBeaconPeriodOver() && !isRngRequested();
  }

  /// @inheritdoc IDrawBeacon
  function canCompleteDraw() external view override returns (bool) {
    return isRngRequested() && isRngCompleted();
  }

  /// @inheritdoc IDrawBeacon
  function calculateNextBeaconPeriodStartTime(uint256 currentTime) external view override returns (uint64) {
    return _calculateNextBeaconPeriodStartTime(beaconPeriodStartedAt, beaconPeriodSeconds, uint64(currentTime));
  }

  /// @inheritdoc IDrawBeacon
  function cancelDraw() external override {
    require(isRngTimedOut(), "DrawBeacon/rng-not-timedout");
    uint32 requestId = rngRequest.id;
    uint32 lockBlock = rngRequest.lockBlock;
    delete rngRequest;
    emit DrawCancelled(msg.sender, requestId, lockBlock);
  }

  /// @inheritdoc IDrawBeacon
  function completeDraw() external override requireCanCompleteRngRequest {
    uint256 randomNumber = rng.randomNumber(rngRequest.id);
    uint32 _nextDrawId = nextDrawId;
    uint64 _beaconPeriodStartedAt = beaconPeriodStartedAt;
    uint32 _beaconPeriodSeconds = beaconPeriodSeconds;
    uint64 _time = _currentTime();

    /**
      * A new DrawLib.Draw contains minimal data regarding the state "core" draw state.
      * Ultimately a Draw.drawId(s) linked with DrawLib.PrizeDistribution(s) creating
      * the complete draw prize payout model: prize tiers, payouts, pick indices, etc...
      * A single Draw struct can have a ONE-TO-MANY relationship with PrizeDistribution settings.
      * Minimizing the total random numbers required to fairly distribute protocol pool payouts.
     */
    DrawLib.Draw memory _draw = DrawLib.Draw({
      winningRandomNumber: randomNumber,
      drawId: _nextDrawId,
      timestamp: _time,
      beaconPeriodStartedAt: _beaconPeriodStartedAt,
      beaconPeriodSeconds: _beaconPeriodSeconds
    });

    /**
      * The DrawBeacon (deployed on L1) will havea Manager role authorized to push history onto DrawHistory.
     */
    drawHistory.pushDraw(_draw);
    
    // to avoid clock drift, we should calculate the start time based on the previous period start time.
    _beaconPeriodStartedAt = _calculateNextBeaconPeriodStartTime(_beaconPeriodStartedAt, _beaconPeriodSeconds, _time);
    beaconPeriodStartedAt = _beaconPeriodStartedAt;
    nextDrawId = _nextDrawId + 1;


    // Reset the rngReqeust state so Beacon period can start again.
    delete rngRequest;

    emit DrawCompleted(msg.sender, randomNumber);
    emit BeaconPeriodStarted(msg.sender, _beaconPeriodStartedAt);
  }

  /// @inheritdoc IDrawBeacon
  function beaconPeriodRemainingSeconds() external view override returns (uint32) {
    return _beaconPeriodRemainingSeconds();
  }

  /// @inheritdoc IDrawBeacon
  function beaconPeriodEndAt() external view override returns (uint64) {
    return _beaconPeriodEndAt();
  }

  /// @inheritdoc IDrawBeacon
  function getLastRngLockBlock() external view override returns (uint32) {
    return rngRequest.lockBlock;
  }

  /// @inheritdoc IDrawBeacon
  function getLastRngRequestId() external view override returns (uint32) {
    return rngRequest.id;
  }

  /// @inheritdoc IDrawBeacon
  function isBeaconPeriodOver() external view override returns (bool) {
    return _isBeaconPeriodOver();
  }

  /// @inheritdoc IDrawBeacon
  function setDrawHistory(IDrawHistory newDrawHistory) external override onlyOwner returns (IDrawHistory) {
    return _setDrawHistory(newDrawHistory);
  }

   /// @inheritdoc IDrawBeacon
  function startDraw() external override requireCanStartDraw {
    (address feeToken, uint256 requestFee) = rng.getRequestFee();
    if (feeToken != address(0) && requestFee > 0) {
      IERC20(feeToken).safeApprove(address(rng), requestFee);
    }

    (uint32 requestId, uint32 lockBlock) = rng.requestRandomNumber();
    rngRequest.id = requestId;
    rngRequest.lockBlock = lockBlock;
    rngRequest.requestedAt = _currentTime();

    emit DrawStarted(msg.sender, requestId, lockBlock);
  }

  /// @inheritdoc IDrawBeacon
  function setBeaconPeriodSeconds(uint32 _beaconPeriodSeconds) external override onlyOwner requireDrawNotInProgress {
    _setBeaconPeriodSeconds (_beaconPeriodSeconds);
  }

  
   /// @inheritdoc IDrawBeacon
  function setRngTimeout(uint32 _rngTimeout) external override onlyOwner requireDrawNotInProgress {
    _setRngTimeout(_rngTimeout);
  }

  /// @inheritdoc IDrawBeacon
  function setRngService(RNGInterface rngService) external override onlyOwner requireDrawNotInProgress {
    require(!isRngRequested(), "DrawBeacon/rng-in-flight");
    rng = rngService;
    emit RngServiceUpdated(rngService);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Calculates when the next beacon period will start
    * @param _beaconPeriodStartedAt The timestamp at which the beacon period started
    * @param _beaconPeriodSeconds The duration of the beacon period in seconds
    * @param _currentTime The timestamp to use as the current time
    * @return The timestamp at which the next beacon period would start
   */
  function _calculateNextBeaconPeriodStartTime(uint64 _beaconPeriodStartedAt, uint32 _beaconPeriodSeconds, uint64 _currentTime) internal view returns (uint64) {
    uint64 elapsedPeriods = (_currentTime - _beaconPeriodStartedAt) / _beaconPeriodSeconds;
    return _beaconPeriodStartedAt + (elapsedPeriods * _beaconPeriodSeconds);
  }

  /**
    * @notice returns the current time.  Used for testing.
    * @return The current time (block.timestamp)
   */
  function _currentTime() internal virtual view returns (uint64) {
    return uint64(block.timestamp);
  }

  /**
    * @notice Returns the timestamp at which the beacon period ends
    * @return The timestamp at which the beacon period ends
   */
  function _beaconPeriodEndAt() internal view returns (uint64) {
    return beaconPeriodStartedAt + beaconPeriodSeconds;
  }

  /**
    * @notice Returns the number of seconds remaining until the prize can be awarded.
    * @return The number of seconds remaining until the prize can be awarded.
   */
  function _beaconPeriodRemainingSeconds() internal view returns (uint32) {
    uint64 endAt = _beaconPeriodEndAt();
    uint64 time = _currentTime();
    if (endAt <= time) {
      return 0;
    }
    return uint256(endAt - time).toUint32();
  }

  /**
    * @notice Returns whether the beacon period is over.
    * @return True if the beacon period is over, false otherwise
   */
  function _isBeaconPeriodOver() internal view returns (bool) {
    uint64 time = _currentTime();
    return _beaconPeriodEndAt() <= time;
  }

  /**
    * @notice Check to see award is in progress.
   */
  function _requireDrawNotInProgress() internal view {
    uint256 currentBlock = block.number;
    require(rngRequest.lockBlock == 0 || currentBlock < rngRequest.lockBlock, "DrawBeacon/rng-in-flight");
  }

  /**
    * @notice Set global DrawHistory variable.
    * @dev    All subsequent Draw requests/completions will be pushed to the new DrawHistory.
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
    * @notice Sets the beacon period in seconds.
    * @param _beaconPeriodSeconds The new beacon period in seconds.  Must be greater than zero.
   */
  function _setBeaconPeriodSeconds(uint32 _beaconPeriodSeconds) internal {
    require(_beaconPeriodSeconds > 0, "DrawBeacon/beacon-period-greater-than-zero");
    beaconPeriodSeconds = _beaconPeriodSeconds;

    emit BeaconPeriodSecondsUpdated(_beaconPeriodSeconds);
  }

  /**
    * @notice Sets the RNG request timeout in seconds.  This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    * @param _rngTimeout The RNG request timeout in seconds.
   */
  function _setRngTimeout(uint32 _rngTimeout) internal {
    require(_rngTimeout > 60, "DrawBeacon/rng-timeout-gt-60-secs");
    rngTimeout = _rngTimeout;
    emit RngTimeoutSet(_rngTimeout);
  }

}
