// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IDrawCalculator.sol";

contract ClaimableDraw is OwnableUpgradeable {

  /**
    * @notice The current draw id. 
    * @dev    The current draw id which correlates to index position in the draws array.
  */
  uint256 public currentDrawId;

  /**
    * @notice Current draw index for managing the draws ring buffer.
  */
  uint256 public currentDrawIndex;

  /**
    * @notice External account/contract authorized to create new draws.
    * @dev    ClaimableDrawPrizeStrategy authorized to create a new draw when capturing the award balance.
  */
  address public drawManager;

  /**
    * @notice A historical list of all draws. The index position is used as the Draw ID.
  */
  Draw[256] internal draws;

  // Mapping of user claimed draws
  // +---------+-------------+
  // | Address | Bytes32     |
  // +---------+-------------+
  // | user    | drawHistory |
  // | user    | drawHistory |
  // +---------+-------------+
  mapping(address => uint96[8]) internal claimedDraws;

  /**
    * @notice Draw model used to calculate a user's claim payout.
  */
  IDrawCalculator public currentCalculator;

  /* ============ Structs ============ */

  struct Draw {
    uint256 randomNumber;
    uint256 prize;
    uint32 timestamp;
    IDrawCalculator calculator;
  }

  /* ============ Events ============ */

  /**
    * @notice Emit when a user has claimed N of draw prizes.
    * @param user             Address of user receiving draw(s) total award payout
    * @param totalPayout      Total award payout calculated using total draw ids and pick indices
  */
  event ClaimedDraw (
    address indexed user,
    uint256 totalPayout
  );

  /**
    * @notice Emit when a new draw calculator is set.
    * @param calculator Address of the new calculator used to calculate award payout
  */
  event DrawCalculatorSet (
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emit when a new draw has been generated.
    * @param drawManager Address of the ClaimableDrawPrizeStrategy authorized to create a new draw
  */
  event DrawManagerSet (
    address indexed drawManager
  );

  /**
    * @notice Emit when a new draw has been created.
    * @param randomNumber Randomly generated number used to calculate draw winning numbers
    * @param timestamp    Epoch timestamp when the draw is created.
    * @param prize        Award amount captured when draw is created.
    * @param calculator   Address of the DrawCalculator used to calculate award payout
  */
  event DrawSet (
    uint256 currentDrawIndex,
    uint256 randomNumber,
    uint256 timestamp,
    uint256 prize,
    IDrawCalculator indexed calculator
  );

  /* ============ Modifiers ============ */

  /**
    * @notice Authorizate caller to create new draw.
    * @dev    Authorizes the calling ClaimableDrawPrizeStrategy to create a new draw during the capture award stage.
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
    * @param _calculator  Address of draw calculator
  */
  function initialize (
    address _drawManager,
    IDrawCalculator _calculator
  ) external initializer {
    __Ownable_init();

    _setDrawManager(_drawManager);
    _setDrawCalculator(_calculator);
  }

  /* ============ External Functions ============ */

  /**
    * @notice Allows users to check the claimable status for a target draw. 
    * @dev    Checks a claimable status for target draw by reading from a user's claim history in claimedDraws.
    *
    * @param user   Address of user
    * @param drawId Unique draw id (index)
  */
  function hasClaimed(address user, uint256 drawId) external view returns (bool) {
    return false;
  }

  /**
    * @notice Reads a user draw claim history.
    * @dev    Reads a user draw claim history, which is stored in a packed bytes32 "word"
    * @param user Address of user
  */
  function userClaimedDraws(address user) external view returns(uint96[8] memory) {
    return claimedDraws[user];
  }

  /**
    * @notice Reads a Draw using the draw id
    * @dev    Reads a Draw using the draw id which equal the index position in the draws array. 
    * @param drawId Address of user
    * @return Draw struct
  */
  function getDraw(uint256 drawId) external view returns(Draw memory) {
    require(drawId <= currentDrawId, "ClaimableDraw/draw-nonexistent");
    return draws[drawId];
  }

  /**
    * @notice External function to set a new authorized draw manager.
    * @dev    External function to set the ClaimableDrawPrizeStrategy, which should be called when a new prize strategy is deployed.
    * @param _newDrawManager  New draw manager address
    * @return New draw manager address
  */
  function setDrawManager(address _newDrawManager) external onlyOwner returns(address) {
    return _setDrawManager(_newDrawManager);
  }

  /**
    * @notice External function to set a new draw calculator.
    * @dev    External function to sets a new draw calculator, which is then sequentially stored in new draw structs. Enabling unique prize calculators for individual draws.
    * @param _newCalculator  New draw calculator address
    * @return New calculator address
  */
  function setDrawCalculator(IDrawCalculator _newCalculator) external onlyOwner returns(IDrawCalculator) {
    return _setDrawCalculator(_newCalculator);
  }

  /**
    * @notice Creates a new draw via a request from the draw manager.
    *
    * @param _randomNumber  Randomly generated draw number
    * @param _timestamp     Epoch timestamp of the draw
    * @param _prize         Award captured when creating a new draw 
    * @return New draw id
  */
  function createDraw(uint256 _randomNumber, uint32 _timestamp, uint256 _prize) public onlyDrawManager returns (uint256) {
    return _createDraw(_randomNumber, _timestamp, _prize);
  }

  /**
    * @notice External function to claim a user's award by passing in the calculated drawIds, drawCalculators and pickIndices. 
    *
    * @param _user             Address of user to claim awards for. Does NOT need to be msg.sender
    * @param _drawIds          Index of the draw in the draws array
    * @param _drawCalculators  Address of the draw calculator for a set of draw ids
    * @param _data             The draw pick indices (uint256[][]) passed as a formatted bytes correlating to the draw ids
    * @return Total claim payout
  */
  function claim(address _user, uint256[][] calldata _drawIds, IDrawCalculator[] calldata _drawCalculators, bytes[] calldata _data) external returns (uint256) {
    return _claim(_user, _drawIds, _drawCalculators, _data);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Internal function to set a new authorized draw manager.
    * @dev    Internal function to set the ClaimableDrawPrizeStrategy, which should be called when a new prize strategy is deployed.
    * @param _newDrawManager  New draw manager address
    * @return  New draw manager address
  */
  function _setDrawManager(address _newDrawManager) internal returns(address) {
    require(_newDrawManager != address(0), "ClaimableDraw/draw-manager-not-zero-address");
    require(_newDrawManager != address(drawManager), "ClaimableDraw/existing-draw-manager-address");

    emit DrawManagerSet(_newDrawManager);
    
    drawManager = _newDrawManager;

    return _newDrawManager;
  }

  /**
    * @notice Internal function to set a new draw calculator.
    * @dev    Internal function to sets a new draw calculator, which is then sequentially stored in new draw structs. Enabling unique prize calculators for individual draws.
    * @param _newCalculator  New draw calculator address
    * @return New calculator address
  */
  function _setDrawCalculator(IDrawCalculator _newCalculator) internal returns(IDrawCalculator) {
    require(address(_newCalculator) != address(0), "ClaimableDraw/calculator-not-zero-address");
    require(_newCalculator != currentCalculator, "ClaimableDraw/existing-calculator-address");

    emit DrawCalculatorSet(_newCalculator);
    
    currentCalculator = _newCalculator;

    return _newCalculator;
  }

  /**
    * @notice Claim a user's award by passing in the calculated drawIds, drawCalculators and pickIndices. 
    * @dev Calculates a user's total award by calling an external drawCalculator with winning drawIds and pickIndices. 
    *
    * @param _user             Address of user to claim awards for. Does NOT need to be msg.sender
    * @param _drawIds          Index of the draw in the draws array
    * @param _drawCalculators  Address of the draw calculator for a set of draw ids
    * @param _data             The draw pick indices (uint256[][]) passed as a formatted bytes correlating to the draw ids
    * @return Total claim payout
  */
  function _claim(
    address _user, 
    uint256[][] calldata _drawIds, 
    IDrawCalculator[] calldata _drawCalculators, 
    bytes[] calldata _data
  ) internal returns (uint256) {
    uint256 drawCalculatorsLength = _drawCalculators.length;
    require(drawCalculatorsLength == _drawIds.length, "ClaimableDraw/invalid-calculator-array");
    uint256 _currentDrawId = currentDrawId; // sload
    uint256 payout;
    uint256 totalPayout;

    for (uint256 calcIndex = 0; calcIndex < drawCalculatorsLength; calcIndex++) {
      IDrawCalculator _drawCalculator = _drawCalculators[calcIndex];
      payout = _calculateAllDraws(_user, _drawIds[calcIndex], _drawCalculator, _data[calcIndex], _currentDrawId);
      totalPayout += payout;
    }

    // claimedDraws[_user] = userDrawClaimHistory; //sstore
    emit ClaimedDraw(_user, totalPayout);

    return totalPayout;
  }

  /**
    * @dev Calculates user payout for a list of draws linked to single draw calculator.
    * @param _user            Address of user
    * @param _drawIds         Array of draws for target draw calculator
    * @param _drawCalculator  Address of draw calculator to determine award payout
    * @param _data            Pick indices for target draw
    * @param _currentDrawId   ID of draw being calculated
    * @return totalPayout Total claim payout
  */
  function _calculateAllDraws(
    address _user, 
    uint256[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data, 
    uint256 _currentDrawId
  ) internal returns (uint256) {
    uint256 payout;
    uint256 totalPayout;
    uint96[8] memory _userClaimedDraws = claimedDraws[_user];

    return totalPayout;
  }

  /**
    * @notice Calculates payout for individual draw.
    * @param _userClaimedDraws User draw payout history
    * @param _drawId           Draw Id
    * @param _payout           Draw payout amount
    * @return Difference between previous draw payout and the current draw payout 
  */
  function _validateDrawPayout(uint256[256] memory _userClaimedDraws, uint256 _drawId, uint256 _payout) internal view returns (uint256) {
    uint256 pastPayout = _userClaimedDraws[_drawId];
    require(_payout > pastPayout, "ClaimableDraw/payout-below-threshold");
    uint256 payoutDiff = _payout - pastPayout;
    return payoutDiff;
  }

  /**
    * @notice Create a new claimable draw.
    * @dev Create a new claimable draw, updates currentDrawId and adds the draw to the draws array.
    * @param _randomNumber  Randomly generated draw number
    * @param _timestamp     Epoch timestamp of the draw
    * @param _prize         Draw's captured award (i.e. prize) amount
    * @return New draw id
  */
  function _createDraw(uint256 _randomNumber, uint32 _timestamp, uint256 _prize) internal returns (uint256) {
    uint256 drawsLength = draws.length;
    IDrawCalculator _currentCalculator = currentCalculator;
    Draw memory _draw = Draw({randomNumber: _randomNumber, prize: _prize, timestamp: _timestamp, calculator: _currentCalculator});
    currentDrawId = drawsLength;
    draws[currentDrawId % 256] = _draw;
    emit DrawSet(drawsLength, _randomNumber, _timestamp, _prize, _currentCalculator);
    
    return drawsLength;
  } 

  /**
    * @notice Calculates the claim index using the draw id.
    * @dev Calculates the claim index, while accounting for a draws expiration status. 
    * @param drawId          Draw id used for calculation
    * @param _currentDrawId  The current draw id
    * @return Absolute draw index in draws ring buffer
  */
  function _drawIdToClaimIndex(uint256 drawId, uint256 _currentDrawId) internal pure returns (uint8) { 
    require(drawId + 256 > _currentDrawId, "ClaimableDraw/claim-expired");
    require(drawId <= _currentDrawId, "ClaimableDraw/drawid-out-of-bounds");

    // How many indices in the past the given draw is
    uint256 deltaIndex = _currentDrawId - drawId;

    // Find absolute draw index by using currentDraw index and delta
    return uint8(_currentDrawId - deltaIndex);
  }

}