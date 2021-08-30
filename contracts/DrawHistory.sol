// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./access/DrawManager.sol";

contract DrawHistory is DrawManager {

  uint256 public nextDrawId;

  uint16 public constant CARDINALITY = 256;

  /**
    * @notice A ring buffer list of all draws.
  */
  Draw[CARDINALITY] private _draws;

  /* ============ Structs ============ */

  struct Draw {
    uint256 drawId;
    uint32 timestamp;
    uint256 randomNumber;
  }

  /* ============ Events ============ */

  /**
    * @notice Emit when a new draw has been created.
    * @param drawId       Draw id
    * @param drawIndex    Draw index in the draws array
    * @param randomNumber Randomly generated number used to calculate draw winning numbers
    * @param timestamp    Epoch timestamp when the draw is created.
  */
  event DrawCreated (
    uint256 drawId,
    uint256 drawIndex,
    uint32 timestamp,
    uint256 randomNumber
  );

  /* ============ Initialize ============ */

  /**
    * @notice Initialize DrawHistory smart contract.
    *
    * @param _drawManager Draw manager address
  */
  function initialize (
    address _drawManager
  ) public initializer {
    __Ownable_init();
    _setDrawManager(_drawManager);
  }

  /* ============ External Functions ============ */

  function draws() external view returns(Draw[CARDINALITY] memory draws) {
    return _draws;
  }

  function drawIdToDrawIndex(uint256 drawId) external pure returns(uint256) {
    return drawId % CARDINALITY;
  }

  /**
    * @notice Reads a Draw using the draw id
    * @dev    Reads a Draw using the draw id which equal the index position in the draws array. 
    * @param drawId DrawID
    * @return Draw struct
  */
  function getDraw(uint256 drawId) external view returns(Draw memory) {
    require(drawId < nextDrawId && nextDrawId > 0, "DrawHistory/draw-out-of-bounds");
    return _draws[drawId % CARDINALITY];
  }

  function getNextDrawId() external view returns(uint256) {
    return nextDrawId;
  }

  /**
    * @notice External function to set an existing draw.
    * @dev    External function to set an existing draw from an authorized draw manager.
    * @param randomNumber  Randomly generated draw number
    * @param timestamp     Epoch timestamp of the draw
    * @return Draw id
  */
  function setDraw(uint256 drawId, uint32 timestamp, uint256 randomNumber) public onlyDrawManagerOrOwner returns (uint256) {
    return _setDraw(drawId, timestamp, randomNumber);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Internal function to create a new draw.
    * @dev    Internal function to create a new draw from an authorized draw manager.
    * @param _timestamp     Epoch timestamp of the draw
    * @param _randomNumber  Randomly generated draw number
    * @return New draw id
  */
  function _createDraw(uint32 _timestamp, uint256 _randomNumber) internal returns (uint256) {
    uint256 _nextDrawId = nextDrawId;
    uint256 _drawIndex = _nextDrawId % CARDINALITY; 
    Draw memory _draw = Draw({drawId: _nextDrawId, timestamp: _timestamp, randomNumber: _randomNumber});
    _draws[_drawIndex] = _draw;
    emit DrawCreated(_nextDrawId, _drawIndex, _timestamp, _randomNumber);
    nextDrawId += 1;
    return _nextDrawId;
  } 

  /**
    * @notice Internal function to set an existing draw.
    * @dev    Internal function to set an existing draw from an authorized draw manager.
    * @param _drawId        Draw id
    * @param _timestamp     Epoch timestamp of the draw
    * @param _randomNumber  Randomly generated draw number
    * @return Draw index
  */
  function _setDraw(uint256 _drawId, uint32 _timestamp, uint256 _randomNumber) internal returns (uint256) {
    require(_drawId < nextDrawId, "DrawHistory/draw-out-of-bounds");
    uint256 _drawIndex = _drawId % CARDINALITY; 
    Draw memory _draw = Draw({drawId: _drawId, timestamp: _timestamp, randomNumber: _randomNumber});
    _draws[_drawIndex] = _draw;
    emit DrawCreated(_drawId, _drawIndex, _timestamp, _randomNumber);
    return _drawIndex;
  } 

}