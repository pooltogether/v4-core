// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./access/AssetManager.sol";
import "./access/DrawManager.sol";
import "./interfaces/IDrawCalculator.sol";

contract ClaimableDraw is AssetManager, DrawManager {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  uint16 public constant CARDINALITY = 8;

  /**
    * @notice The next draw id.
    * @dev    The next draw id which correlates to index position in the draws array.
  */
  uint256 public nextDrawId;

  /**
    * @notice A historical list of all draws. The index position is used as the Draw ID.
  */
  Draw[CARDINALITY] internal draws;

  // Mapping of user draw payout history
  // +---------+-------------------+
  // | Address | uint96[]          |
  // +---------+-------------------+
  // | user    | userPayoutHistory |
  // | user    | userPayoutHistory |
  // +---------+-------------------+
  mapping(address => uint96[CARDINALITY]) internal userPayoutHistory;

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
    * @notice Emit when a new draw has been created.
    * @param randomNumber Randomly generated number used to calculate draw winning numbers
    * @param timestamp    Epoch timestamp when the draw is created.
    * @param prize        Award amount captured when draw is created.
    * @param calculator   Address of the DrawCalculator used to calculate award payout
  */
  event DrawSet (
    uint256 drawId,
    uint256 drawIndex,
    uint256 randomNumber,
    uint256 timestamp,
    uint256 prize,
    IDrawCalculator indexed calculator
  );

  /**
    * @notice Emitted when ERC20 tokens are withdrawn from the claimable draw.
    * @param from Address that transferred funds.
    * @param to Address that received funds.
    * @param amount Amount of tokens transferred.
    * @param token ERC20 token transferred.
  */
  event TransferredERC20(
    address indexed from,
    address indexed to,
    uint256 amount,
    IERC20Upgradeable indexed token
  );

  /* ============ Initialize ============ */

  /**
    * @notice Initialize claimable draw smart contract.
    *
    * @param _drawManager Draw manager address.
    * @param _calculator Draw calculator address.
  */
  function initialize (
    address _drawManager,
    IDrawCalculator _calculator
  ) external initializer {
    __Ownable_init();

    setDrawManager(_drawManager);
    _setDrawCalculator(_calculator);
  }

  /* ============ External Functions ============ */

  /**
    * @notice Allows users to check the claimable status for a target draw.
    * @dev    Checks a claimable status for target draw by reading from a user's claim history in claimedDraws.
    *
    * @param user   Address of user
    * @param drawId Draw id
  */
  function userDrawPayout(address user, uint256 drawId) external view returns (uint96) {
    uint96[CARDINALITY] memory _userPayoutHistory = userPayoutHistory[user];
    return _userPayoutHistory[_drawIdToClaimIndex(drawId, nextDrawId - 1)];
  }

  /**
    * @notice Reads a user draw claim history.
    * @dev    Reads a user draw claim history, which is stored in a packed bytes32 "word"
    * @param user Address of user
  */
  function userDrawPayouts(address user) external view returns(uint96[CARDINALITY] memory) {
    return userPayoutHistory[user];
  }

  /**
    * @notice Reads a Draw using the draw id
    * @dev    Reads a Draw using the draw id which equal the index position in the draws array.
    * @param drawId Address of user
    * @return Draw struct
  */
  function getDraw(uint256 drawId) external view returns(Draw memory) {
    uint256 _currentDrawId = nextDrawId - 1;
    uint8 drawIndex = _drawIdToClaimIndex(drawId, _currentDrawId);
    return draws[drawIndex];
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

  /**
    * @notice Transfer ERC20 tokens to this contract.
    * @dev This function is only callable by the owner or asset manager.
    * @param _erc20Token ERC20 token to transfer.
    * @param _amount Amount of tokens to transfer.
    * @return true if operation is successful.
  */
  function depositERC20(IERC20Upgradeable _erc20Token, uint256 _amount) external onlyOwnerOrAssetManager returns (bool) {
    return _transferERC20(_erc20Token, msg.sender, address(this), _amount);
  }

  /**
    * @notice Transfer ERC20 tokens out of this contract.
    * @dev This function is only callable by the owner asset manager.
    * @param _erc20Token ERC20 token to transfer.
    * @param _to Recipient of the tokens.
    * @param _amount Amount of tokens to transfer.
    * @return true if operation is successful.
  */
  function withdrawERC20(IERC20Upgradeable _erc20Token, address _to, uint256 _amount) external onlyOwnerOrAssetManager returns (bool) {
    return _transferERC20(_erc20Token, address(this), _to, _amount);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Calculates the claim index using the draw id.
    * @dev Calculates the claim index, while accounting for a draws expiration status.
    * @param _drawId         Draw id used for calculation
    * @param _currentDrawId  The current draw id
    * @return Absolute draw index in draws ring buffer
  */
  function _drawIdToClaimIndex(uint256 _drawId, uint256 _currentDrawId) internal pure returns (uint8) {
    require(_drawId + CARDINALITY > _currentDrawId, "ClaimableDraw/claim-expired");
    require(_drawId <= _currentDrawId, "ClaimableDraw/drawid-out-of-bounds");

    return uint8(_drawId % CARDINALITY);
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
    * @notice Create a new claimable draw.
    * @dev Create a new claimable draw, updates currentDrawId and adds the draw to the draws array.
    * @param _randomNumber  Randomly generated draw number
    * @param _timestamp     Epoch timestamp of the draw
    * @param _prize         Draw's captured award (i.e. prize) amount
    * @return New draw id
  */
  function _createDraw(uint256 _randomNumber, uint32 _timestamp, uint256 _prize) internal returns (uint256) {
    uint256 _nextDrawId = nextDrawId;
    IDrawCalculator _currentCalculator = currentCalculator;
    Draw memory _draw = Draw({randomNumber: _randomNumber, prize: _prize, timestamp: _timestamp, calculator: _currentCalculator});
    uint256 _drawIndex = _nextDrawId % CARDINALITY;
    draws[_drawIndex] = _draw;
    nextDrawId = _nextDrawId + 1;
    emit DrawSet(_nextDrawId, _drawIndex, _randomNumber, _timestamp, _prize, _currentCalculator);
    return _nextDrawId;
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
    uint256 totalPayout;
    uint256 drawCollectionPayout;

    for (uint256 calcIndex = 0; calcIndex < drawCalculatorsLength; calcIndex++) {
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
    uint256[] calldata _drawIds,
    IDrawCalculator _drawCalculator,
    bytes calldata _data
  ) internal returns (uint256) {
    uint256 drawCollectionPayout;
    uint96[CARDINALITY] memory _userPayoutHistory = userPayoutHistory[_user];

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
    uint96[CARDINALITY] memory _userPayoutHistory,
    uint256[] calldata _drawIds,
    IDrawCalculator _drawCalculator,
    bytes calldata _data
  ) internal returns (uint256 totalPayout, uint96[CARDINALITY] memory userPayoutHistory) {
    uint96[] memory prizesAwardable;
    uint256[] memory prizes = new uint256[](_drawIds.length);
    uint32[] memory timestamps = new uint32[](_drawIds.length);
    uint256[] memory randomNumbers = new uint256[](_drawIds.length);
    userPayoutHistory = _userPayoutHistory;

    (randomNumbers, timestamps, prizes) = _createDrawClaimsInput(_drawIds, _drawCalculator, randomNumbers, timestamps, prizes);
    prizesAwardable = _drawCalculator.calculate(_user, randomNumbers, timestamps, prizes, _data);
    require(_drawIds.length == prizesAwardable.length, "ClaimableDraw/invalid-prizes-awardable");

    uint96 prize;
    for (uint256 prizeIndex = 0; prizeIndex < prizesAwardable.length; prizeIndex++) {
      prize = prizesAwardable[prizeIndex];
      (prize, userPayoutHistory) = _validateDrawPayout(userPayoutHistory, (_drawIds[prizeIndex] % CARDINALITY), prize);
      totalPayout += prize;
    }
  }

  function _createDrawClaimsInput(
    uint256[] calldata _drawIds,
    IDrawCalculator _drawCalculator,
    uint256[] memory _randomNumbers,
    uint32[] memory _timestamps,
    uint256[] memory _prizes
  ) internal view returns(uint256[] memory, uint32[] memory, uint256[] memory) {
    uint256 _currentDrawId = nextDrawId - 1; // sload
    for (uint256 drawIndex = 0; drawIndex < _drawIds.length; drawIndex++) {
      Draw memory _draw = draws[_drawIdToClaimIndex(_drawIds[drawIndex], _currentDrawId)];
      require(_draw.calculator == _drawCalculator && address(_draw.calculator) != address(0), "ClaimableDraw/calculator-address-invalid");
      _randomNumbers[drawIndex] = _draw.randomNumber;
      _timestamps[drawIndex] = uint32(_draw.timestamp);
      _prizes[drawIndex] = _draw.prize;
    }

    return (_randomNumbers, _timestamps, _prizes);
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
    uint96[CARDINALITY] memory _userPayoutHistory,
    uint256 _drawIndex,
    uint96 _payout
  ) internal pure returns (uint96, uint96[CARDINALITY] memory) {
    uint96 pastPayout = _userPayoutHistory[_drawIndex];
    require(_payout > pastPayout, "ClaimableDraw/payout-below-threshold");
    uint96 payoutDiff = _payout - pastPayout;
    _userPayoutHistory[_drawIndex] = payoutDiff;
    return (payoutDiff, _userPayoutHistory);
  }

  /**
    * @notice Transfer ERC20 tokens held by this contract to the recipient address.
    * @dev This function is only callable by the asset manager.
    * @param _erc20Token ERC20 token to transfer.
    * @param _from Sender of the tokens.
    * @param _to Recipient of the tokens.
    * @param _amount Amount of tokens to transfer.
    * @return true if operation is successful.
  */
  function _transferERC20(IERC20Upgradeable _erc20Token, address _from, address _to, uint256 _amount) internal returns (bool) {
    require(address(_erc20Token) != address(0), "ClaimableDraw/ERC20-not-zero-address");
    require(_from != _to, "ClaimableDraw/from-different-than-to-address");

    if (_from == address(this)) {
      _erc20Token.safeTransfer(_to, _amount);
    }

    if (_to == address(this)) {
      _erc20Token.safeTransferFrom(_from, _to, _amount);
    }

    emit TransferredERC20(_from, _to, _amount, _erc20Token);

    return true;
  }

}
