// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IDrawCalculator.sol";

contract ClaimableDraw is OwnableUpgradeable {

  // The latest draw id 
  uint256 public currentDrawId;

  // The current draw index for handling expired claimable prizes
  uint256 public currentDrawIndex;

  // External account responsible for creating a new draw.
  address public drawManager;

  // A history of all draws
  Draw[] internal draws;

  // Mapping of user claimed draws
  // +---------+-------------+
  // | Address | Bytes32     |
  // +---------+-------------+
  // | user    | drawHistory |
  // | user    | drawHistory |
  // +---------+-------------+
  mapping(address => bytes32) internal claimedDraws;

  IDrawCalculator public currentCalculator;

  /* ============ Structs ============ */

  struct Draw {
    uint256 randomNumber;
    uint256 timestamp;
    uint256 prize;
    IDrawCalculator calculator;
  }

  /* ============ Events ============ */
  /**
    * @notice Emit when a user has claimed N of draw prizes.
  */
  event Claimed (
    address indexed user,
    bytes32 userClaimedDraws,
    uint256 totalPayout
  );

  /**
    * @notice Emit when a new draw calculator is set.
  */
  event DrawCalculatorSet (
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emit when the smart contract is initialized.
  */
  event ClaimableDrawInitialized (
    address indexed drawManager
  );

  /**
    * @notice Emit when a new draw has been generated.
  */
  event DrawSet (
    uint256 randomNumber,
    uint256 timestamp,
    uint256 prize,
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emit when a new draw has been generated.
  */
  event DrawManagerSet (
    address indexed drawManager
  );

  /* ============ Modifiers ============ */

  /**
    * @notice Manage who can generate a new draw.
  */
  modifier onlyDrawManager() {
    require(msg.sender == drawManager, "ClaimableDraw/unauthorized-draw-manager");
    _;
  }

  /* ============ Initialize ============ */

  /**
    * @notice Initialize claimable draw smart contract.
    *
    * @param _drawManager  Address of draw manager
  */
  function initialize (
    address _drawManager
  ) public initializer {
    __Ownable_init();

    drawManager = _drawManager;

    emit ClaimableDrawInitialized(_drawManager);
  }

  /* ============ External Functions ============ */

  /**
    * @notice Check user claim status for individual draw.
    *
    * @param user    Address of user
    * @param drawId  Unique draw id (index)
  */
  function hasClaimed(address user, uint256 drawId) external view returns (bool) {
    uint8  drawIndex  = _drawIdToClaimIndex(drawId, currentDrawIndex);
    bytes32 userDrawClaimHistory = claimedDraws[user]; //sload
    return _readLastClaimFromClaimedHistory(userDrawClaimHistory, drawIndex);
  }

  /**
    * @notice Reads the current user draw claim history.
    *
    * @param user  Address of user
  */
  function userClaimedDraws(address user) external view returns(bytes32) {
    return claimedDraws[user];
  }

  /**
    * @notice Sets the draw manager address.
    *
    * @param _drawManager  New draw manager address
  */
  function setDrawManager(address _drawManager) external onlyOwner returns(address) {
    require(_drawManager != address(0), "ClaimableDraw/draw-manager-not-zero-address");
    require(_drawManager != address(drawManager), "ClaimableDraw/existing-draw-manager-address");

    emit DrawManagerSet(_drawManager);
    
    return drawManager = _drawManager;
  }

  /**
    * Sets the current draw calculator.
    *
    * @param _currentCalculator  New draw calculator address
  */
  function setDrawCalculator(IDrawCalculator _currentCalculator) external onlyOwner returns(IDrawCalculator) {
    require(address(_currentCalculator) != address(0), "ClaimableDraw/calculator-not-zero-address");
    require(_currentCalculator != currentCalculator, "ClaimableDraw/existing-calculator-address");

    emit DrawCalculatorSet(_currentCalculator);
    
    return currentCalculator = _currentCalculator;
  }

  /**
    * @notice Sets the draw manager address.
    *
    * @param randomNumber  Randomly generated draw number
    * @param timestamp     Epoch timestamp of the draw
    * @param prize         Total draw prize
  */
  function createDraw(uint256 randomNumber, uint256 timestamp, uint256 prize) public onlyDrawManager returns (uint256) {
    return _createDraw(randomNumber, timestamp, prize);
  }

  function claim(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes calldata data) public returns (uint256) {
    return _claim(user, drawIds, drawCalculators, data);
  }

  /* ============ Internal Functions ============ */

  function _claim(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes calldata data) internal returns (uint256){
    require(drawCalculators.length == drawIds.length, "ClaimableDraw/invalid-calculator-array");
    bytes32 userDrawClaimHistory = claimedDraws[user]; //sload
    uint256 _currentDrawId = currentDrawId; // sload

    uint256 totalPayout;
    for (uint256 calcIndex = 0; calcIndex < drawCalculators.length; calcIndex++) {
      uint256 payout;
      IDrawCalculator _drawCalculator = drawCalculators[calcIndex];
    
      (payout, userDrawClaimHistory) = _calculateAllDraws(user, drawIds[calcIndex], _drawCalculator, data, _currentDrawId, userDrawClaimHistory);
      totalPayout = totalPayout + payout;
    }

    claimedDraws[user] = userDrawClaimHistory; //sstore

    emit Claimed(user, userDrawClaimHistory, totalPayout);

    return totalPayout;
  }

  /**
    * @dev Calculates user payout for a list of draws linked to single draw calculator.
    *
    * @param user  Address of user
    * @param drawIds  Array of draws for target draw calculator
    * @param drawCalculator  Address of draw calculator to determine award payout
    * @param data  Pick indices for target draw
    * @param _currentDrawId  ID of draw being calculated
    * @param _claimedDraws  User's claimed draw history
  */
  function _calculateAllDraws(address user, uint256[] calldata drawIds, IDrawCalculator drawCalculator, bytes calldata data, uint256 _currentDrawId, bytes32 _claimedDraws) internal returns (uint256 totalPayout, bytes32 userClaimedDraws) {
    uint256[] memory prizes = new uint256[](drawIds.length);
    uint32[] memory timestamps = new uint32[](drawIds.length);
    uint256[] memory randomNumbers = new uint256[](drawIds.length);

    for (uint256 drawIndex = 0; drawIndex < drawIds.length; drawIndex++) {
      Draw memory _draw = draws[drawIds[drawIndex]];
      require(_draw.calculator == drawCalculator, "ClaimableDraw/calculator-address-invalid");

      prizes[drawIndex] = _draw.prize;
      timestamps[drawIndex] = uint32(_draw.timestamp);
      randomNumbers[drawIndex] = _draw.randomNumber;
      
      userClaimedDraws = _claimDraw(_claimedDraws, drawIds[drawIndex], _currentDrawId);
    }

    totalPayout += drawCalculator.calculate(user, randomNumbers, timestamps, prizes, data);
  }

  /**
    * @dev Create a new claimable draw.
    *
    * @param randomNumber  Randomly generated draw number
    * @param timestamp     Epoch timestamp of the draw
    * @param prize         Total draw prize
  */
  function _createDraw(uint256 randomNumber, uint256 timestamp, uint256 prize) internal returns (uint256){
    Draw memory _draw = Draw(randomNumber, timestamp,prize, currentCalculator);
    currentDrawId = draws.length;
    draws.push(_draw);

    emit DrawSet(randomNumber, timestamp,prize, currentCalculator);
    
    return currentDrawId;
  } 

  /**
    * @dev Update the draw claim history for target draw id.
    *
    * @param userClaimedDraws  Current user claimed draws
    * @param drawId            ID of draw to update 
    * @param _currentDrawId    Current draw id (i.e. last draw id)
  */
  function _claimDraw(bytes32 userClaimedDraws, uint256 drawId, uint256 _currentDrawId) internal returns (bytes32) {
    uint8 drawIndex = _drawIdToClaimIndex(drawId, _currentDrawId);
    bool isClaimed = _readLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);

    require(!isClaimed, "ClaimableDraw/user-previously-claimed");

    return _writeLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);
  }

  /**
    * @dev Calculate the claim index using the draw id.
    *
    * @param drawId          Draw id used for calculation
    * @param _currentDrawId  The current draw id
  */
  function _drawIdToClaimIndex(uint256 drawId, uint256 _currentDrawId) view internal returns (uint8){
    require(drawId + 256 > _currentDrawId, "ClaimableDraw/claim-expired");
    require(drawId <= _currentDrawId, "ClaimableDraw/drawid-out-of-bounds");

    // How many indices in the past the given draw is
    uint256 deltaIndex = _currentDrawId - drawId;

    // Find absolute draw index by using currentDraw index and delta
    return uint8(currentDrawIndex - deltaIndex);
  }

   /**
    * @dev Read the user claime status of a target draw.
    *
    * @param _userClaimedDraws  User claim draw history (256 bit word)
    * @param _drawIndex         The index within that word (0 to 7)
  */
  function _readLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bool) {
    uint256 mask = (uint256(1)) << (_drawIndex);
    return ((uint256(_userClaimedDraws) & mask) >> (_drawIndex)) != 0;    
  }

  /**
    * @dev Updates a 256 bit word with a 32 bit representation of a block number at a particular index
    *
    * @param _userClaimedDraws  User claim draw history (256 bit word)
    * @param _drawIndex         The index within that word (0 to 7)
  */
  function _writeLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bytes32) { 
    uint256 mask =  (uint256(1)) << (_drawIndex);
    return bytes32(uint256(_userClaimedDraws) | mask); 
  }

}