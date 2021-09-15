// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "hardhat/console.sol";
import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/IDrawCalculator.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";

contract ClaimableDraw is OwnerOrManager {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /// @notice The cardinality of the users payout/claim history
  uint16 public constant PAYOUT_CARDINALITY = 8;

  /// @notice DrawHistory smart contract
  IDrawHistory public drawHistory;

  /// @notice Mapping of drawId to the drawCalculator
  mapping(uint32 => IDrawCalculator) public drawCalculatorAddresses;

  /** 
    /* User draw claim payout history
    /* +---------+-------------------+
    /* | Address | uint96[]          |
    /* +---------+-------------------+
    /* | user    | userPayoutHistory |
    /* | user    | userPayoutHistory |
    /* +---------+-------------------+
  */
  mapping(address => uint96[PAYOUT_CARDINALITY]) internal userPayoutHistory;
  
  /// @notice User highest claimed draw id
  mapping(address => uint32) internal _userHighestClaimedDrawId;
  
  /* ============ Events ============ */

  /**
    * @notice Emitted when a user has claimed N of draw prizes.
    * @param user             Address of user receiving draw(s) total award payout
    * @param totalPayout      Total award payout calculated using total draw ids and pick indices
  */
  event ClaimedDraw (
    address indexed user,
    uint256 totalPayout
  );

  /**
    * @notice Emitted when a new draw calculator is set.
    * @param calculator Address of the new calculator used to calculate award payout
  */
  event DrawCalculatorSet (
    uint256 drawId,
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emitted when a new draw history address is set.
    * @param drawHistory Address of the new draw drawHistory contract
  */
  event DrawHistorySet (
    IDrawHistory indexed drawHistory
  );

  /**
    * @notice Emitted when ERC20 tokens are withdrawn from the claimable draw.
    * @param token ERC20 token transferred.
    * @param to Address that received funds.
    * @param amount Amount of tokens transferred.
  */
  event ERC20Withdrawn(
    IERC20Upgradeable indexed token,
    address indexed to,
    uint256 amount
  );


  /* ============ Initialize ============ */

  /**
    * @notice Initialize claimable draw smart contract.
    * @param _drawCalculatorManager  Address of the draw calculator manager
    * @param _drawHistory            Address of the draw history contract
  */
  function initialize (
    address _drawCalculatorManager,
    IDrawHistory _drawHistory
  ) external initializer {
    __Ownable_init(); 

    _setDrawHistory(_drawHistory);
    _setManager(_drawCalculatorManager);
  }

  /* ============ External Functions ============ */

  /**
    * @notice Reads a user draw claim payout history for target draw id.
    * @dev    Reads a user draw claim payout history for target draw id.
    * @param user   Address of user
    * @param drawId Draw id
  */
  function userDrawPayout(address user, uint32 drawId) external view returns (uint96) {
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory = userPayoutHistory[user]; // sload
    return _userPayoutHistory[_wrapCardinality(drawId)];
  }

  /**
    * @notice Reads a user draw claim payout history.
    * @dev    Reads a user draw claim payout history.
    * @param user Address of user
  */
  function userDrawPayouts(address user) external view returns(uint96[PAYOUT_CARDINALITY] memory) {
    return userPayoutHistory[user];
  }

  /**
    * @notice Sets DrawCalculator reference for individual draw id.
    * @dev    Sets DrawCalculator reference for individual draw id.
    * @param _drawId         Draw id
    * @param _newCalculator  DrawCalculator address
    * @return New calculator address
  */
  function setDrawCalculator(uint32 _drawId, IDrawCalculator _newCalculator) external onlyManagerOrOwner returns(IDrawCalculator) {
    return _setDrawCalculator(_drawId, _newCalculator);
  }
  
  /**
    @notice Set global DrawHistory smart contract reference.
    @dev    Set global DrawHistory smart contract reference.
    @param _drawHistory DrawHistory address
  */
  function setDrawHistory(IDrawHistory _drawHistory) external onlyManagerOrOwner returns (IDrawHistory) {
    return _setDrawHistory(_drawHistory);
  }

  /**
    * @notice External function to claim a user's award by passing in the calculated drawIds, drawCalculators and pickIndices. 
    * @param _user             Address of user to claim awards for. Does NOT need to be msg.sender
    * @param _drawIds          Index of the draw in the draws array
    * @param _drawCalculators  Address of the draw calculator for a set of draw ids
    * @param _data             The draw pick indices (uint256[][]) passed as a formatted bytes correlating to the draw ids
    * @return Total claim payout
  */
  function claim(address _user, uint32[][] calldata _drawIds, IDrawCalculator[] calldata _drawCalculators, bytes[] calldata _data) external returns (uint256) {

    uint32 _highestClaimedDrawId = _userHighestClaimedDrawId[_user];
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory = userPayoutHistory[_user];
    DrawLib.Draw memory _newestDrawFromHistory = drawHistory.getNewestDraw();

    if(_newestDrawFromHistory.drawId >= PAYOUT_CARDINALITY) {
      _userPayoutHistory = _resetUserDrawClaimedHistory(
        _wrapCardinality(_newestDrawFromHistory.drawId), 
        (_newestDrawFromHistory.drawId - _highestClaimedDrawId),
        _userPayoutHistory
      );
    }

    return _claim(_user, _drawIds, _drawCalculators, _data, _userPayoutHistory, _newestDrawFromHistory);
  }

  /**
    * @notice Transfer ERC20 tokens out of this contract.
    * @dev This function is only callable by the owner asset manager.
    * @param _erc20Token ERC20 token to transfer.
    * @param _to Recipient of the tokens.
    * @param _amount Amount of tokens to transfer.
    * @return true if operation is successful.
  */
  function withdrawERC20(IERC20Upgradeable _erc20Token, address _to, uint256 _amount) external onlyManagerOrOwner returns (bool) {
    require(address(_to) != address(0), "ClaimableDraw/ERC20-not-zero-address");
    require(address(_erc20Token) != address(0), "ClaimableDraw/ERC20-not-zero-address");
    _erc20Token.safeTransfer(_to, _amount);
    emit ERC20Withdrawn(_erc20Token, _to, _amount);
    return true;
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Sets DrawCalculator reference for individual draw id.
    * @dev    Sets DrawCalculator reference for individual draw id.
    * @param _newCalculator  DrawCalculator address
    * @return New calculator address
   */
  function _setDrawCalculator(uint32 _drawId, IDrawCalculator _newCalculator) internal returns(IDrawCalculator) {
    require(address(_newCalculator) != address(0), "ClaimableDraw/calculator-not-zero-address");
    // do we need a check for not overwriting an existing calculator?

    drawCalculatorAddresses[_drawId] = _newCalculator; 
    emit DrawCalculatorSet(_drawId, _newCalculator);
    return _newCalculator;
  }

  /**
    @notice Set global DrawHistory smart contract reference.
    @dev    Set global DrawHistory smart contract reference.
    @param _drawHistory DrawHistory address
  */
  function _setDrawHistory(IDrawHistory _drawHistory) internal returns (IDrawHistory) 
  {
    require(address(_drawHistory) != address(0), "ClaimableDraw/draw-history-not-zero-address");
    drawHistory = _drawHistory;
    emit DrawHistorySet(_drawHistory);
    return _drawHistory;
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
    uint32[][] calldata _drawIds, 
    IDrawCalculator[] calldata _drawCalculators, 
    bytes[] calldata _data,
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory,
    DrawLib.Draw memory _newestDrawFromHistory
  ) internal returns (uint256) {
    uint256 totalPayout;
    uint256 drawCollectionPayout;
    require(_drawCalculators.length == _drawIds.length, "ClaimableDraw/invalid-calculator-array");
    for (uint8 calcIndex = 0; calcIndex < _drawCalculators.length; calcIndex++) {
      // Validate collection of draw ids are within the acceptable range.
      _validateDrawIdRange(_drawIds[calcIndex], _newestDrawFromHistory);
      IDrawCalculator _drawCalculator = _drawCalculators[calcIndex];
      (drawCollectionPayout, _userPayoutHistory) = _calculate(_user, _drawIds[calcIndex], _drawCalculator, _data[calcIndex], _userPayoutHistory);
      totalPayout += drawCollectionPayout;
    }
    _saveUserHighestClaimedDrawId(_user, _drawIds);
    userPayoutHistory[_user] = _userPayoutHistory;

    emit ClaimedDraw(_user, totalPayout);

    return totalPayout;
  }

  /**
    * @dev Calculates user payout for a list of draws linked to single draw calculator.
    * @param _user            Address of user
    * @param _drawIds         Array of draws for target draw calculator
    * @param _drawCalculator  Address of draw calculator to determine award payout
    * @param _data            Pick indices for target draw
    * @return Total draw collection payout
  */
  function _calculate(
    address _user, 
    uint32[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data,
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory
  ) internal returns (uint256, uint96[PAYOUT_CARDINALITY] memory) {
    uint256 drawCollectionPayout;
    (drawCollectionPayout, _userPayoutHistory) = _calculateDrawCollectionPayout(_user, _userPayoutHistory, _drawIds, _drawCalculator, _data);
    return (drawCollectionPayout, _userPayoutHistory);
  }

  /**
    * @dev Calculates user payout for a list of draws linked to single draw calculator.
    * @param _user              Address of user
    * @param _userPayoutHistory  User draw claim payout history
    * @param _drawIds           Array of draws for target draw calculator
    * @param _drawCalculator    Address of draw calculator to determine award payout
    * @param _data              Pick indices for target draw
    * @return totalPayout Total claim payout
  */
  function _calculateDrawCollectionPayout(
    address _user,
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory, 
    uint32[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data
  ) internal returns (uint256, uint96[PAYOUT_CARDINALITY] memory) {
    uint96 prize;
    uint256 totalPayout;
    uint96[] memory prizesAwardable;
    DrawLib.Draw[] memory _draws = drawHistory.getDraws(_drawIds); // CALL
    prizesAwardable = _drawCalculator.calculate(_user, _draws, _data);  // CALL
    require(_drawIds.length == prizesAwardable.length, "ClaimableDraw/invalid-prizes-awardable");

    for (uint256 prizeIndex = 0; prizeIndex < prizesAwardable.length; prizeIndex++) {
      prize = prizesAwardable[prizeIndex];
      (prize, _userPayoutHistory) = _validateDrawPayout(_userPayoutHistory, _wrapCardinality(_drawIds[prizeIndex]), prize);
      totalPayout += prize;
    }

    return (totalPayout, _userPayoutHistory);
  }

  /* ============ Helper Functions ============ */

  function _resetUserDrawClaimedHistory(
    uint32 _resetPosition,
    uint32 _resetAmount, 
    uint96[PAYOUT_CARDINALITY] memory _claimHistory
  ) internal returns (uint96[PAYOUT_CARDINALITY] memory) {
    uint8 _pointer = _wrapCardinality(_resetPosition);

    if(_resetAmount >= PAYOUT_CARDINALITY) {
      for (uint256 index = 0; index < PAYOUT_CARDINALITY; index++) {
        _claimHistory[index] = 0;
      }
    } else {
      for (uint256 index = 0; index < _resetAmount; index++) {
        if(index == PAYOUT_CARDINALITY) break;
        _claimHistory[_pointer - index] = 0;
      }
    }
    return _claimHistory;
  }
  /**
    * @dev Calculates ring buffer index
    * @param _user User address
    * @param _drawIdsCollection User address
    * @return Highest claimed draw id
  */
  function _saveUserHighestClaimedDrawId(address _user, uint32[][] calldata _drawIdsCollection) internal returns (uint32) {
    uint32 _newHighestClaimedDrawId;
    uint32 ___userHighestClaimedDrawId = _userHighestClaimedDrawId[_user];

    for (uint256 drawIdsCollectionIndex = 0; drawIdsCollectionIndex < _drawIdsCollection.length; drawIdsCollectionIndex++) {
      uint32[] memory _drawIds = _drawIdsCollection[drawIdsCollectionIndex];
      for (uint256 index = 0; index < _drawIds.length; index++) {
        uint32 _drawId =  _drawIds[index];
        _newHighestClaimedDrawId = _drawId > _newHighestClaimedDrawId ? _drawId : _newHighestClaimedDrawId;
      } 
    }

    if ( _newHighestClaimedDrawId >= ___userHighestClaimedDrawId) {
      _userHighestClaimedDrawId[_user] = _newHighestClaimedDrawId;
      return _newHighestClaimedDrawId;
    }

    return ___userHighestClaimedDrawId;
  }

  /**
    * @notice Modulo index with ring buffer cardinality.
    * @dev    Modulo index with ring buffer cardinality.
    * @param _index Index 
    * @return Ring buffer pointer
  */
  function _wrapCardinality(uint32 _index) internal pure returns (uint8) { 
    return uint8(_index % PAYOUT_CARDINALITY);
  }

  /* ============ Validation Functions ============ */


  /**
    * @notice Calculates payout for individual draw.
    * @param _userPayoutHistory User draw claim payout history
    * @param _drawIndex         Draw index in user claimed draw payout history
    * @param _payout            Draw payout amount
    * @return Difference between previous draw payout and the current draw payout 
    * @return Updated user draw claim payout history
  */
  function _validateDrawPayout(
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory, 
    uint256 _drawIndex, 
    uint96 _payout
  ) internal pure returns (uint96, uint96[PAYOUT_CARDINALITY] memory) {
    uint96 pastPayout = _userPayoutHistory[_drawIndex];
    require(_payout >= pastPayout, "ClaimableDraw/payout-below-threshold");
    uint96 payoutDiff = _payout - pastPayout;
    _userPayoutHistory[_drawIndex] = payoutDiff;
    return (payoutDiff, _userPayoutHistory);
  }

  /**
    * @dev Validate claim draw ids to be within PAYOUT_CARDINALITY range.
    * @param _drawIds     Array of draw ids grouped for target draw calculator
    * @param _newestDrawFromHistory Acceptable draw id minimum (supplied ids must be greater)
    * @return Boolean if all draw ids in range
  */
  function _validateDrawIdRange(uint32[] calldata _drawIds, DrawLib.Draw memory _newestDrawFromHistory) internal pure returns (bool) { 
    uint32 _drawIdFloor = _newestDrawFromHistory.drawId > PAYOUT_CARDINALITY ? _newestDrawFromHistory.drawId - PAYOUT_CARDINALITY : 0;
    for (uint256 drawIdsIndex = 0; drawIdsIndex < _drawIds.length; drawIdsIndex++) {
      require(_drawIds[drawIdsIndex] >= _drawIdFloor, "ClaimableDraw/draw-id-out-of-range");
    }
    return true;
  }
}