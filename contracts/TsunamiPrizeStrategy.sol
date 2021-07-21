// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

// Libraries & Inheritance
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@pooltogether/pooltogether-contracts/contracts/prize-pool/PrizePoolInterface.sol";
import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";

import "./interfaces/IWaveModel.sol";
import "./interfaces/IPickHistory.sol";
import "./interfaces/IClaimer.sol";
import "./interfaces/ITicket.sol";

contract TsunamiPrizeStrategy is OwnableUpgradeable,
                                 ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for  uint256;
    using SafeCastUpgradeable for  uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

   /* ============ Variables ============ */
    // The total number of draws
    uint256 public drawCount;

    // The pick history address.
    IPickHistory public pickHistory;
    
    // The claim aggregator address.
    IClaimer public claimer;

    // The pending wave model address.
    IWaveModel public pendingModel;

    // The active wave model address.
    IWaveModel public activeModel;

    // The pending wave model address.
    IERC20Upgradeable public token;

    // Prize period
    uint256 public prizePeriodSeconds;
    uint256 public prizePeriodStartedAt;

    // Contract Interfaces
    PrizePoolInterface public prizePool;
    ITicket public ticket;
    IERC20Upgradeable public sponsorship;
    RNGInterface public rng;

    // RNG Request Timeout.  In fact, this is really a "complete award" timeout.
    uint32 public rngRequestTimeout;

    // Current RNG Request
    RngRequest internal rngRequest;

    // Wave Model update timelock configuration
    uint256 internal _timelockWaveSet;
    uint256 internal _timelockPeriod = 604800; // 7 Days

    // Manage the unclaimed interest
    uint256 internal _claimedExpiredAwards;
    bool internal _claimExpiredAwardsDuringCompleteAward;

   /* ============ Structs ============ */

   struct Draw {
     uint256 prize;
     uint256 totalDeposits;
     uint256 timestamp;
     uint256 winningNumber;
     uint256 drawCount;
     IWaveModel model;
   }
   
   struct WaveModel {
     IWaveModel model;
     string name;
   }

   struct RngRequest {
    uint32 id;
    uint32 lockBlock;
    uint32 requestedAt;
  }

  // Mapping of draw timestamp to draw struct
  // +---------------+-------------+
  // | DrawTimestamp | DrawStruct  |
  // +---------------+-------------+
  // | Timestamp     | DrawModel   |
  // | Timestamp     | DrawModel   |
  // +---------------+-------------+
  mapping(uint256 => Draw) public drawHistory;
  // Draw[] public drawHistory;

  // Mapping of wave model address wave model struct
  // +--------------+-------------+
  // | ModelAddress | ModelStruct |
  // +--------------+-------------+
  // | ModelA       | WaveModel   |
  // | ModelA       | WaveModel   |
  // +--------------+-------------+
  mapping(IWaveModel => WaveModel) public waveModels;

  // Mapping of user to user draw history
  mapping(address => uint256) public userDraws;

  /* ============ Events ============ */
  event Initialized(
    uint256 _prizePeriodStart,
    uint256 _prizePeriodSeconds,
    PrizePoolInterface _prizePool,
    IERC20Upgradeable _ticket,
    IERC20Upgradeable _sponsorship,
    RNGInterface _rng
  );

  event AwardClaimed(
    address indexed user,
    uint256 prize
  );

  event ClaimerSet(
    IClaimer indexed claimer
  );
  
  event RngServiceUpdated(
    RNGInterface indexed rngService
  );

  event RngRequestTimeoutSet(
    uint32 rngRequestTimeout
  );

  event PrizePeriodSecondsUpdated(
    uint256 prizePeriodSeconds
  );

  event WaveModelProposed(
    IWaveModel indexed model
  );
  
  event WaveModelActivated(
    IWaveModel indexed model
  );


  /* ============ Modifiers ============ */
  modifier onlyClaimAggregator() {
    require(msg.sender == address(claimer), "TsunamiPrizeStrategy/invalid-claimer");
    _;
  }

  modifier requireAwardNotInProgress() {
    _requireAwardNotInProgress();
    _;
  }

  function _requireAwardNotInProgress() internal view {
    uint256 currentBlock = _currentBlock();
    require(rngRequest.lockBlock == 0 || currentBlock < rngRequest.lockBlock, "PeriodicPrizeStrategy/rng-in-flight");
  }

  modifier requireCanCompleteAward() {
    require(isRngRequested(), "PeriodicPrizeStrategy/rng-not-requested");
    require(isRngCompleted(), "PeriodicPrizeStrategy/rng-not-complete");
    _;
  }

  /* ============ Initialize ============ */

  function initialize (
    uint256 _prizePeriodStart,
    uint256 _prizePeriodSeconds,
    PrizePoolInterface _prizePool,
    IERC20Upgradeable _ticket,
    IERC20Upgradeable _sponsorship,
    RNGInterface _rng
  ) public initializer {
    __Ownable_init();

    require(address(_prizePool) != address(0), "PeriodicPrizeStrategy/prize-pool-not-zero");
    require(address(_ticket) != address(0), "PeriodicPrizeStrategy/ticket-not-zero");
    require(address(_sponsorship) != address(0), "PeriodicPrizeStrategy/sponsorship-not-zero");
    require(address(_rng) != address(0), "PeriodicPrizeStrategy/rng-not-zero");

    prizePool = _prizePool;
    ticket = _ticket;
    rng = _rng;
    sponsorship = _sponsorship;

    _setPrizePeriodSeconds(_prizePeriodSeconds);

    prizePeriodSeconds = _prizePeriodSeconds;
    prizePeriodStartedAt = _prizePeriodStart;
  }

  /* ============ External Functions ============ */

  /**
     * @notice Claim award prize passing by passing user draws and pick indices. 
     *
     * @param user                   Address of the user
     * @param draws                  List of the draws
     * @param pickIndices            An array of pickIndices arrays
     */
  function claim(address user, uint256[] calldata draws, uint256[][] calldata pickIndices) external onlyClaimAggregator {
    _claim(user, draws, pickIndices);
  }

  /**
    * @notice Claim the award interest from the prize pool and create draw history.
    *
    * @param winningNumber             Winning (random) number to generate 
  */
  function completeAward(uint256 winningNumber) external requireCanCompleteAward returns (Draw memory draw){
    if(claimExpiredAwardsDuringCompleteAward) {
      _claimExpiredCapturedAward();
    }

    // Calculate the current draw awarded prize interest. 
    uint256 prize = _completeAward();

    uint256 totalDeposits;
    uint256 timestamp = _currentTimestamp();
    // IWaveModel _model = activeModel;

    draw = Draw(prize, totalDeposits, timestamp, winningNumber, drawCount++, activeModel);

    drawHistory[timestamp] = draw;
  }

  /**
    * @notice Claim the expired captured award.
    *
  */
  function claimExpiredCapturedAward() external onlyOwner requireCanCompleteAward returns (uint256 reclaimedPrized){


    return reclaimedPrized;
  }


  /**
    * Sets a pending wave model to be activated by governance 
    * called by authorized core contracts.
    *
    * @param  _claimer    Claim aggregator address
    */
  function setClaimer(IClaimer _claimer) external onlyOwner returns (bool) {
    require(address(_claimer) != address(0), "TsunamiPrizeStrategy/claimer-not-zero-address");
    require(address(_claimer) != address(claimer), "TsunamiPrizeStrategy/claimer-address-set");

    claimer = _claimer;

    emit ClaimerSet(_claimer);

    return true;
  }

  /**
    * @notice Sets pending wave model to be activated by governance 
    *
    * @param _model      The address of the WaveModel
    * @param _name      The address of the WaveModel
    */
  function setPendingWaveModel(IWaveModel _model, string calldata _name) external onlyOwner returns (bool) {
    require(address(_model) != address(0), "TsunamiPrizeStrategy/model-not-zero-address");
    require(address(_model) != address(pendingModel), "TsunamiPrizeStrategy/model-not-zero-address");

    WaveModel memory model = WaveModel(_model, _name);
    waveModels[_model] = model;

    _timelockWaveSet = _currentTimestamp();

    emit WaveModelProposed(_model);

    return true;
  }

  /**
    * Sets a pending wave model to be activated by governance 
    * called by authorized core contracts.
    *
    */
  function setActiveWaveModel() external onlyOwner returns (bool){
    // The timelock period for activating a new model has elapsed.
    require(_timelockWaveSet + _timelockPeriod >= _currentTimestamp(), "TsunamiPrizeStrategy/timelock-enabled");

    IWaveModel _pendingModel = pendingModel;
    activeModel = _pendingModel;

    emit WaveModelActivated(_pendingModel);

    return true;
  }

  /**
    * @notice Allows the owner to set the RNG request timeout in seconds.  This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    *
    * @param _rngRequestTimeout The RNG request timeout in seconds.
  */
  function setRngRequestTimeout(uint32 _rngRequestTimeout) external onlyOwner requireAwardNotInProgress {
    _setRngRequestTimeout(_rngRequestTimeout);
  }

  /**
     * @notice Allows the owner to set the prize period in seconds.
     *
     * @param _prizePeriodSeconds The new prize period in seconds.  Must be greater than zero.
     */
  function setPrizePeriodSeconds(uint256 _prizePeriodSeconds) external onlyOwner requireAwardNotInProgress {
    _setPrizePeriodSeconds(_prizePeriodSeconds);
  }

  function canCompleteAward() external view returns (bool) {
    return isRngRequested() && isRngCompleted();
  }

  function isRngRequested() public view returns (bool) {
    return rngRequest.id != 0;
  }

  function isRngCompleted() public view returns (bool) {
    return rng.isRequestComplete(rngRequest.id);
  }

  function getLastRngLockBlock() external view returns (uint32) {
    return rngRequest.lockBlock;
  }

  function getLastRngRequestId() external view returns (uint32) {
    return rngRequest.id;
  }

  function setRngService(RNGInterface _rng) external onlyOwner requireAwardNotInProgress returns (bool) {
    require(!isRngRequested(), "PeriodicPrizeStrategy/rng-in-flight");

    rng = _rng;
    emit RngServiceUpdated(_rng);

    return true;
  }


  /* ============ Internal Functions ============ */

  /**
    * @dev Award users with prize by calculating total winners via the external model.
    *
    * @param user                   Address of the user
    * @param draws                  List of the draws by timestamp
    * @param pickIndices            An array of pickIndices arrays
  */
  function _claim(address user, uint256[] calldata draws, uint256[][] calldata pickIndices) internal nonReentrant {
    ITicket _ticket = ticket;
    IPickHistory _pickHistory = pickHistory;

    // Find the last draw 
    uint256 drawHistoryLength = drawCount;
    Draw memory lastDraw = drawHistory[drawHistoryLength.sub(1)];

    // User Information

    for (uint256 index = 0; index < draws.length; index++) {
      Draw memory _draw = drawHistory[draws[index]];
      IWaveModel memory _drawModel = _draw.model;

      // Get the user balance at the time of the draw
      uint256 userBalance = _ticket.getBalance(user, _draw.timestamp);

      // Calculate the users prize award using the draws prize calculation model. 
      uint256 prizeAmount = _drawModel.calculate(
        lastDraw.winningNumber, 
        lastDraw.prize, 
        lastDraw.totalDeposits, 
        userBalance, 
        lastDraw.winningNumber
      );

      // Update the userDraws claimed state
      _setUserDrawClaimedStatus(_draw.drawCount);
    }


    _awardUserPrizeAmount(user, prizeAmount);
    emit AwardClaimed(user, prizeAmount);

  }

  /**
    * @notice Set the claimed status for a user draw history.
    *
  */
  function _setUserDrawClaimedStatus(address _user, uint256 _drawNumber) internal {
    uint256 userDrawHistory = userDraws[_user];

  }

  /**
    * @notice Claim the expired captured award.
    *
  */
  function _claimExpiredCapturedAward() internal returns (uint256 reclaimedPrized){
    reclaimedAwardPrize = _calculateUnclaimedAwards();
    _claimedExpiredAwards = _claimedExpiredAwards + reclaimedAwardPrize;
    return reclaimedPrized;
  }

  /**
    * @notice Calculate the total unclaimed awards after expiration period
    *
  */
  function _calculateUnclaimedAwards() internal returns (uint256 calculatedUnclaimedAwards){
    
    // INSERT MAGIC TO CALCULATE THE TOTAL UNCALIMED EXPIRED AWARDS

    return calculatedUnclaimedAwards;
  }

  /**
    * @dev Capture the award balance from external prize pool.
    *
  */
  function _findDraw(uint256 _timestamp) internal returns (Draw memory draw) {
    draw = drawHistory[_timestamp];
  }

  /**
    * @dev Capture the award balance from external prize pool.
    *
  */
  function _completeAward() internal returns (uint256 prize) {
    prize = prizePool.captureAwardBalance();
    if(_claimedExpiredAwards > 0) {
      prize = prize + _claimedExpiredAwards;
    }
  }


  function _awardUserPrizeAmount(address user, uint256 amount) internal {
    prizePool.award(user, amount, address(ticket));
  }

  /**
    * @notice Sets the prize period in seconds.
    *
    * @param _prizePeriodSeconds The new prize period in seconds.  Must be greater than zero.
  */
  function _setPrizePeriodSeconds(uint256 _prizePeriodSeconds) internal returns (uint256 prizePeriodSeconds) {
    require(_prizePeriodSeconds > 0, "PeriodicPrizeStrategy/prize-period-greater-than-zero");
    prizePeriodSeconds = _prizePeriodSeconds;

    emit PrizePeriodSecondsUpdated(_prizePeriodSeconds);
  }

  /**
    * @notice Sets the RNG request timeout in seconds.  This is the time that must elapsed before the RNG request can be cancelled and the pool unlocked.
    *
    * @param _rngRequestTimeout The RNG request timeout in seconds.
  */
  function _setRngRequestTimeout(uint32 _rngRequestTimeout) internal returns (uint256 rngRequestTimeout){
    require(_rngRequestTimeout > 60, "PeriodicPrizeStrategy/rng-timeout-gt-60-secs");
    rngRequestTimeout = _rngRequestTimeout;

    emit RngRequestTimeoutSet(_rngRequestTimeout);
  }

  /* ============ Helper Functions ============ */

  /**
    * @notice Read the current block number.
    *
    * @return The current blocknumber (block.number)
  */
  function _currentBlock() internal virtual view returns (uint256) {
    return block.number;
  }
  
  /**
    * @notice Read the current block timestamp.
    *
    * @return The current block timestamp (block.timestamp)
  */
  function _currentTimestamp() internal virtual view returns (uint256) {
    return block.timestamp;
  }

  // Get bit value at position
  // function _getBit(bytes1 a, uint256 n) internal returns (bool) {
  //     return a & shiftLeft(0x01, n) != 0;
  // }
    
  // // Set bit value at position
  // function _setBit(bytes1 a, uint256 n) internal returns (bytes1) {
  //     return a | shiftLeft(0x01, n);
  // }

  // function shiftLeft(bytes1 a, uint8 n) internal returns (bytes1) {
  //   var shifted = uint8(a) * 2 ** n;
  //   return bytes1(shifted);
  // }
}