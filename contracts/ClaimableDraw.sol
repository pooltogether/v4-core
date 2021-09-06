// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/IDrawHistory.sol";

import "./libraries/DrawLib.sol";

contract ClaimableDraw is OwnerOrManager {

  ///@notice The cardinality of the users payout/claim history
  uint16 public constant PAYOUT_CARDINALITY = 8;

  ///@notice Mapping of drawId to the drawCalculator
  mapping(uint32 => IDrawCalculator) public drawCalculatorAddresses;

  // Mapping of user draw payout history
  // +---------+-------------------+
  // | Address | uint96[]          |
  // +---------+-------------------+
  // | user    | userPayoutHistory |
  // | user    | userPayoutHistory |
  // +---------+-------------------+
  mapping(address => uint96[PAYOUT_CARDINALITY]) internal userPayoutHistory;

  ///@notice DrawHistory address
  IDrawHistory public drawHistory;

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
    * @notice Allows users to check the claimable status for a target draw. 
    * @dev    Checks a claimable status for target draw by reading from a user's claim history in claimedDraws.
    *
    * @param user   Address of user
    * @param drawId Draw id
  */
  function userDrawPayout(address user, uint32 drawId) external view returns (uint96) {
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory = userPayoutHistory[user];// sload
    return _userPayoutHistory[_drawIdToClaimIndex(drawId)];
  }

  /**
    * @notice Reads a user draw claim history.
    * @dev    Reads a user draw claim history, which is stored in a packed bytes32 "word"
    * @param user Address of user
  */
  function userDrawPayouts(address user) external view returns(uint96[PAYOUT_CARDINALITY] memory) {
    return userPayoutHistory[user];
  }

  /**
    * @notice External function to set a new draw calculator.
    * @dev    External function to sets a new draw calculator, which is then sequentially stored in new draw structs. Enabling unique prize calculators for individual draws.
    * @param _drawId    Draw id
    * @param _newCalculator  New draw calculator address
    * @return New calculator address
  */
  function setDrawCalculator(uint32 _drawId, IDrawCalculator _newCalculator) external onlyManagerOrOwner returns(IDrawCalculator) {
    return _setDrawCalculator(_drawId, _newCalculator);
  }
  
  /**
    @notice External function to set a new draw calculator. Only callable by manager or owner.
    @param _drawHistory Address of the draw history contract
  */
  function setDrawHistory(IDrawHistory _drawHistory) external onlyManagerOrOwner returns (IDrawHistory) {
    return _setDrawHistory(_drawHistory);
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
  function claim(address _user, uint8[][] calldata _drawIds, IDrawCalculator[] calldata _drawCalculators, bytes[] calldata _data) external returns (uint256) {
    return _claim(_user, _drawIds, _drawCalculators, _data);
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
    * @notice Calculates the claim index using the draw id.
    * @dev Calculates the claim index, while accounting for a draws expiration status. 
    * @param _drawId         Draw id used for calculation
    * @return Absolute draw index in draws ring buffer
  */
  function _drawIdToClaimIndex(uint32 _drawId) internal pure returns (uint8) { 
    // require(_drawId + PAYOUT_CARDINALITY > _currentDrawId, "ClaimableDraw/claim-expired");
    // require(_drawId <= _currentDrawId, "ClaimableDraw/drawid-out-of-bounds");

    return uint8(_drawId % PAYOUT_CARDINALITY);
  }


  /**
    * @notice Internal function to set a new draw calculator.
    * @dev    Internal function to sets a new draw calculator, which is then sequentially stored in new draw structs. Enabling unique prize calculators for individual draws.
    * @param _newCalculator  New draw calculator address
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
    @notice Internal function to set a new draw calculator.
    @param _drawHistory Address of the draw history contract
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
    uint8[][] calldata _drawIds, 
    IDrawCalculator[] calldata _drawCalculators, 
    bytes[] calldata _data
  ) internal returns (uint256) {
    
    uint256 drawCalculatorsLength = _drawCalculators.length;
    require(drawCalculatorsLength == _drawIds.length, "ClaimableDraw/invalid-calculator-array");
    uint256 totalPayout;
    uint256 drawCollectionPayout;

    for (uint8 calcIndex = 0; calcIndex < drawCalculatorsLength; calcIndex++) {
      IDrawCalculator _drawCalculator = _drawCalculators[calcIndex];
      drawCollectionPayout = _calculate(_user, _drawIds[calcIndex], _drawCalculator, _data[calcIndex]);
      totalPayout += drawCollectionPayout;
    }

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
    uint8[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data
  ) internal returns (uint256) {
    
    uint256 drawCollectionPayout;
    uint96[PAYOUT_CARDINALITY] memory _userPayoutHistory = userPayoutHistory[_user];

    (drawCollectionPayout, _userPayoutHistory) = _calculateDrawCollectionPayout(_user, _userPayoutHistory, _drawIds, _drawCalculator, _data);
    userPayoutHistory[_user] = _userPayoutHistory;

    return drawCollectionPayout;
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
    uint8[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data
  ) internal returns (uint256 totalPayout, uint96[PAYOUT_CARDINALITY] memory userPayoutHistory) {
    
    uint96[] memory prizesAwardable;
    userPayoutHistory = _userPayoutHistory;

    DrawLib.Draw[] memory _draws = drawHistory.getDraws(_drawIds); // CALL

    prizesAwardable = _drawCalculator.calculate(_user, _draws, _data);  // CALL
    
    require(_drawIds.length == prizesAwardable.length, "ClaimableDraw/invalid-prizes-awardable");

    uint96 prize;
    for (uint256 prizeIndex = 0; prizeIndex < prizesAwardable.length; prizeIndex++) {
      prize = prizesAwardable[prizeIndex];
      (prize, userPayoutHistory) = _validateDrawPayout(userPayoutHistory, (_drawIds[prizeIndex] % PAYOUT_CARDINALITY), prize);
      totalPayout += prize;
    }
  }

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
    require(_payout > pastPayout, "ClaimableDraw/payout-below-threshold");
    uint96 payoutDiff = _payout - pastPayout;
    _userPayoutHistory[_drawIndex] = payoutDiff;
    return (payoutDiff, _userPayoutHistory);
  }

}