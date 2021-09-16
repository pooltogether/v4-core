// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/IDrawCalculator.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";

/**
  * @title  PoolTogether V4 DrawCalculator
  * @author PoolTogether Inc Team
  * @notice Distributes PrizePool captured interest as individual draw payouts.  
*/
contract ClaimableDraw is OwnerOrManager {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /* ============ Global Variables ============ */

  /// @notice User draw claims ring buffer cardinality
  uint16 public constant CARDINALITY = 8;

  /// @notice DrawHistory address
  IDrawHistory public drawHistory;

  /// @notice Draw.drawId to DrawCalculator mapping
  mapping(uint32 => IDrawCalculator) public drawCalculatorAddresses;

  /// @notice User address to draw claims ring buffer mapping
  mapping(address => uint96[CARDINALITY]) internal _userDrawClaims;

  /* ============ Events ============ */

  /**
    * @notice Emitted when a user has claimed N draw payouts.
    * @param user        User address receiving draw claim payouts
    * @param totalPayout Payout for N draw claims 
  */
  event ClaimedDraw (
    address indexed user,
    uint256 totalPayout
  );

  /**
    * @notice Emitted when a DrawCalculator is linked to a Draw ID.
    * @param drawId     Draw ID
    * @param calculator DrawCalculator address
  */
  event DrawCalculatorSet (
    uint256 drawId,
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emitted when a global DrawHistory variable is set.
    * @param drawHistory DrawHistory address
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
    * @notice Initialize ClaimableDraw smart contract.
    * @param _manager     Manager address
    * @param _drawHistory DrawHistory address
  */
  function initialize (
    address _manager,
    IDrawHistory _drawHistory
  ) external initializer {
    __Ownable_init(); 
    _setManager(_manager);

    drawHistory = _drawHistory;
    emit DrawHistorySet(_drawHistory);
  }

  /* ============ View/Pure Functions ============ */

  /**
    * @notice Read user's draw claim history for target Draw ID.
    * @param user   User address
    * @param drawId Draw ID
  */
  function userDrawClaim(address user, uint32 drawId) external view returns (uint96) {
    uint96[CARDINALITY] memory _claims = _userDrawClaims[user]; // sload
    return _claims[_wrapCardinality(drawId)];
  }

  /**
    * @notice Read user's complete draw claim history.
    * @param user Address of user
  */
  function userDrawClaims(address user) external view returns(uint96[CARDINALITY] memory) {
    return _userDrawClaims[user];
  }

  /**
    * @notice Calculates payout for individual draw.
    * @param _userClaims User claim history
    * @param _index      Index in ring buffer 
    * @param _payout     Draw payout
    * @return Difference between previous draw payout and the current draw payout 
    * @return User draw claim history
  */
  function _updateUserDrawPayout(
    uint96[CARDINALITY] memory _userClaims, 
    uint256 _index, 
    uint96 _payout
  ) internal pure returns (uint96, uint96[CARDINALITY] memory) {
    uint96 pastPayout = _userClaims[_index];
    require(_payout > pastPayout, "ClaimableDraw/payout-below-threshold");
    uint96 payoutDiff = _payout - pastPayout;
    _userClaims[_index] = payoutDiff;
    return (payoutDiff, _userClaims);
  }

  /**
    * @notice Modulo Draw ID with ring buffer cardinality.
    * @param _drawId Draw ID 
    * @return Ring buffer index
  */
  function _wrapCardinality(uint32 _drawId) internal pure returns (uint8) { 
    return uint8(_drawId % CARDINALITY);
  }

  /* ============ External Functions ============ */

  /**
    * @notice Claim a user ticket payouts via a collection of draw ids and pick indices. 
    * @param _user             Address of user to claim awards for. Does NOT need to be msg.sender
    * @param _drawIds          Draw IDs from global DrawHistory reference
    * @param _drawCalculators  DrawCalculator addresses
    * @param _data             The draw pick indices (uint256[][]) passed as a formatted bytes correlating to the draw ids
    * @return Total claim payout
  */
  function claim(address _user, uint32[][] calldata _drawIds, IDrawCalculator[] calldata _drawCalculators, bytes[] calldata _data) external returns (uint256) {
    uint256 drawCalculatorsLength = _drawCalculators.length;
    require(drawCalculatorsLength == _drawIds.length, "ClaimableDraw/invalid-calculator-array");
    uint256 totalPayout;
    uint256 drawCollectionPayout;

    for (uint256 i = 0; i < drawCalculatorsLength; i++) {
      IDrawCalculator _drawCalculator = _drawCalculators[i];
      drawCollectionPayout = _calculate(_user, _drawIds[i], _drawCalculator, _data[i]);
      totalPayout += drawCollectionPayout;
    }

    emit ClaimedDraw(_user, totalPayout);

    return totalPayout;
  }

  /**
    * @notice Sets DrawCalculator reference for individual draw id.
    * @param _drawId         Draw id
    * @param _newCalculator  DrawCalculator address
    * @return New DrawCalculator address
  */
  function setDrawCalculator(uint32 _drawId, IDrawCalculator _newCalculator) external onlyManagerOrOwner returns(IDrawCalculator) {
    // Restrict the manager from setting a Draw ID linked DrawCalculator if previously set.
    if(_msgSender() != owner()) {
      require(address(_newCalculator) != address(0), "ClaimableDraw/calculator-not-zero-address");
      IDrawCalculator _currentCalculator = drawCalculatorAddresses[_drawId];
      require(address(_currentCalculator) == address(0), "ClaimableDraw/draw-calculator-previous-set");
    }

    drawCalculatorAddresses[_drawId] = _newCalculator; 
    emit DrawCalculatorSet(_drawId, _newCalculator);
    return _newCalculator;
  }

  /**
    @notice Set global DrawHistory reference.
    @param _drawHistory DrawHistory address
    * @return New DrawHistory address
  */
  function setDrawHistory(IDrawHistory _drawHistory) external onlyManagerOrOwner returns (IDrawHistory) {
    require(address(_drawHistory) != address(0), "ClaimableDraw/draw-history-not-zero-address");
    drawHistory = _drawHistory;
    emit DrawHistorySet(_drawHistory);
    return _drawHistory;
  }

  /**
    * @notice Transfer ERC20 tokens out of this contract.
    * @dev    This function is only callable by the owner or manager.
    * @param _erc20Token ERC20 token to transfer.
    * @param _to Recipient of the tokens.
    * @param _amount Amount of tokens to transfer.
    * @return true if operation is successful.
  */
  function withdrawERC20(IERC20Upgradeable _erc20Token, address _to, uint256 _amount) external onlyManagerOrOwner returns (bool) {
    require(_to != address(0), "ClaimableDraw/recipient-not-zero-address");
    require(address(_erc20Token) != address(0), "ClaimableDraw/ERC20-not-zero-address");
    _erc20Token.safeTransfer(_to, _amount);
    emit ERC20Withdrawn(_erc20Token, _to, _amount);
    return true;
  }

  /* ============ Internal Functions ============ */

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
    bytes calldata _data
  ) internal returns (uint256) {
    uint256 _payout;
    uint96[CARDINALITY] memory _claims = _userDrawClaims[_user];

    (_payout, _claims) = _calculateDrawCollectionPayout(_user, _claims, _drawIds, _drawCalculator, _data);
    _userDrawClaims[_user] = _claims;

    return _payout;
  }

  /**
    * @dev Calculates user payout for a list of draws linked to single draw calculator.
    * @param _user           User address
    * @param _claims         User draw claim history
    * @param _drawIds        Array of draws for target draw calculator
    * @param _drawCalculator Address of draw calculator to determine award payout
    * @param _data           Pick indices for target draw
    * @return totalPayout Total claim payout
  */
  function _calculateDrawCollectionPayout(
    address _user,
    uint96[CARDINALITY] memory _claims, 
    uint32[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data
  ) internal returns (uint256 totalPayout, uint96[CARDINALITY] memory _userClaims) {
    
    uint96[] memory prizesAwardable;
    _userClaims = _claims;

    DrawLib.Draw[] memory _draws = drawHistory.getDraws(_drawIds); // CALL

    prizesAwardable = _drawCalculator.calculate(_user, _draws, _data);  // CALL
    
    require(_drawIds.length == prizesAwardable.length, "ClaimableDraw/invalid-prizes-awardable");

    uint96 prize;
    for (uint256 prizeIndex = 0; prizeIndex < prizesAwardable.length; prizeIndex++) {
      prize = prizesAwardable[prizeIndex];
      (prize, _userClaims) = _updateUserDrawPayout(_userClaims, _wrapCardinality(_drawIds[prizeIndex]), prize);
      totalPayout += prize;
    }
  }

}