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
  Draw[] internal draws;

  // Mapping of user claimed draws
  // +---------+-------------+
  // | Address | Bytes32     |
  // +---------+-------------+
  // | user    | drawHistory |
  // | user    | drawHistory |
  // +---------+-------------+
  mapping(address => bytes32) internal claimedDraws;

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
    * @param userClaimedDraws User's updated claim history after executing succesful draw claims
    * @param totalPayout      Total award payout calculated using total draw ids and pick indices
  */
  event ClaimedDraw (
    address indexed user,
    bytes32 userClaimedDraws,
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
    return _readUsersDrawClaimStatusFromClaimedHistory(claimedDraws[user], _drawIdToClaimIndex(drawId, currentDrawId));
  }

  /**
    * @notice Reads a user draw claim history.
    * @dev    Reads a user draw claim history, which is stored in a packed bytes32 "word"
    * @param user Address of user
  */
  function userClaimedDraws(address user) external view returns(bytes32) {
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
    bytes32 userDrawClaimHistory = claimedDraws[_user]; //sload
    uint256 _currentDrawId = currentDrawId; // sload
    uint256 payout;
    uint256 totalPayout;

    for (uint256 calcIndex = 0; calcIndex < drawCalculatorsLength; calcIndex++) {
      IDrawCalculator _drawCalculator = _drawCalculators[calcIndex];
      (payout, userDrawClaimHistory) = _calculateAllDraws(_user, _drawIds[calcIndex], _drawCalculator, _data[calcIndex], _currentDrawId, userDrawClaimHistory);
      totalPayout += payout;
    }

    claimedDraws[_user] = userDrawClaimHistory; //sstore
    emit ClaimedDraw(_user, userDrawClaimHistory, totalPayout);

    return totalPayout;
  }

  /**
    * @dev Calculates user payout for a list of draws linked to single draw calculator.
    * @param _user            Address of user
    * @param _drawIds         Array of draws for target draw calculator
    * @param _drawCalculator  Address of draw calculator to determine award payout
    * @param _data            Pick indices for target draw
    * @param _currentDrawId   ID of draw being calculated
    * @param _claimedDraws    User's claimed draw history
    * @return totalPayout Total claim payout
    * @return userDrawClaimHistory Updated userDrawClaimHistory
  */
  function _calculateAllDraws(
    address _user, 
    uint256[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data, 
    uint256 _currentDrawId, 
    bytes32 _claimedDraws
  ) internal returns (uint256 totalPayout, bytes32 userDrawClaimHistory) {
    uint256[] memory prizes = new uint256[](_drawIds.length);
    uint32[] memory timestamps = new uint32[](_drawIds.length);
    uint256[] memory randomNumbers = new uint256[](_drawIds.length);
    userDrawClaimHistory = _claimedDraws;

    for (uint256 drawIndex = 0; drawIndex < _drawIds.length; drawIndex++) {
      Draw memory _draw = draws[_drawIds[drawIndex]];
      require(_draw.calculator == _drawCalculator, "ClaimableDraw/calculator-address-invalid");
      prizes[drawIndex] = _draw.prize;
      timestamps[drawIndex] = uint32(_draw.timestamp);
      randomNumbers[drawIndex] = _draw.randomNumber;
      userDrawClaimHistory = _updateUsersDrawClaimStatus(userDrawClaimHistory, _drawIds[drawIndex], _currentDrawId);
    }

    totalPayout += _drawCalculator.calculate(_user, randomNumbers, timestamps, prizes, _data);
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
    uint256 drawsLength =  draws.length;
    IDrawCalculator _currentCalculator = currentCalculator;
    Draw memory _draw = Draw({randomNumber: _randomNumber, prize: _prize, timestamp: _timestamp, calculator: _currentCalculator});
    currentDrawId = drawsLength;
    draws.push(_draw);
    emit DrawSet(drawsLength, _randomNumber, _timestamp, _prize, _currentCalculator);
    
    return drawsLength;
  } 

  /**
    * @notice Update the draw claim history for target draw id.
    * @dev Update the draw claim history for target draw id.
    * @param _userDrawClaimHistory  Current user claimed draws
    * @param _drawId                ID of draw to update 
    * @param _currentDrawId         Current draw id (i.e. last draw id)
    * @return Updated userDrawClaimHistory
  */
  function _updateUsersDrawClaimStatus(bytes32 _userDrawClaimHistory, uint256 _drawId, uint256 _currentDrawId) internal pure returns (bytes32) {
    uint8 drawIndex = _drawIdToClaimIndex(_drawId, _currentDrawId);
    bool isClaimed = _readUsersDrawClaimStatusFromClaimedHistory(_userDrawClaimHistory, drawIndex);
    require(!isClaimed, "ClaimableDraw/user-previously-claimed");

    return _writeUsersDrawClaimStatusFromClaimedHistory(_userDrawClaimHistory, drawIndex);
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


   /**
    * @dev Read the last user claimed status of a target draw.
    *
    * @param _userClaimedDraws  User claim draw history (256 bit word)
    * @param _drawIndex         The index within that word (0 to 7)
    * @return User's draw claim status
  */
  function _readUsersDrawClaimStatusFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bool) {
    uint256 mask = (uint256(1)) << (_drawIndex);
    return ((uint256(_userClaimedDraws) & mask) >> (_drawIndex)) != 0;    
  }

  /**
    * @dev Updates a 256 bit word with a 32 bit representation of a block number at a particular index
    *
    * @param _userClaimedDraws  User claim draw history (256 bit word)
    * @param _drawIndex         The index within that word (0 to 7)
    * @return Updated User's draw claim history
  */
  function _writeUsersDrawClaimStatusFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bytes32) { 
    uint256 mask =  (uint256(1)) << (_drawIndex);
    return bytes32(uint256(_userClaimedDraws) | mask); 
  }

}