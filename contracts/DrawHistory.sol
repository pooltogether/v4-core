// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";

contract DrawHistory is IDrawHistory, OwnerOrManager {
  
  /**
    * @notice Next ring buffer index position when pushing a new draw. 
  */
  uint32 public nextDrawIndex;

  /**
    * @notice Ring buffer array size.
  */
  uint16 public constant CARDINALITY = 256;

  /**
    * @notice Draws ring buffer array.
  */
  DrawLib.Draw[CARDINALITY] private _draws;

  /* ============ Events ============ */

  /**
    * @notice Emit when a new draw has been created.
    * @param drawIndex    Draw index in the draws array
    * @param drawId       Draw id
    * @param timestamp    Epoch timestamp when the draw is created.
    * @param winningRandomNumber Randomly generated number used to calculate draw winning numbers
  */
  event DrawSet (
    uint256 drawIndex,
    uint32 drawId,
    uint32 timestamp,
    uint256 winningRandomNumber
  );

  /* ============ Initialize ============ */

  /**
    * @notice Initialize DrawHistory smart contract.
    *
    * @param _manager Draw manager address
  */
  function initialize (
    address _manager
  ) public initializer {
    __Ownable_init();
    _setManager(_manager);
  }

  /* ============ External Functions ============ */
  
  /**
    * @notice Read all draws.
    * @dev    Return all draws from the draws ring buffer.
    * @return Draws array
  */
  function draws() external view returns(DrawLib.Draw[CARDINALITY] memory) {
    return _draws;
  }

  /**
    * @notice External function to calculate draw index using the draw id.
    * @dev    Use the draw id to calculate the draw index position in the draws ring buffer.
    * @param drawId Draw id
    * @return Draw index
  */
  function drawIdToDrawIndex(uint32 drawId) external view returns(uint32) {
    return _drawIdToDrawIndex(drawId);
  }

  /**
    * @notice Read draw from the draws ring buffer.
    * @dev    Read draw from the draws ring buffer using the draw id.
    * @param drawId Draw id
    * @return Draw struct
  */
  function getDraw(uint32 drawId) external view override returns(DrawLib.Draw memory) {
    uint32 drawIndex = _drawIdToDrawIndex(drawId);
    return _draws[drawIndex];
  }

  /**
    * @notice Read multiple draws from the draws ring buffer.
    * @dev    Read multiple draws from the draws ring buffer from an array of draw ids.
    * @param drawIds DrawID
    * @return draws Draw structs
  */
  function getDraws(uint32[] calldata drawIds) external view override returns(DrawLib.Draw[] memory) {
    uint32 drawIndex;
    DrawLib.Draw[] memory draws = new DrawLib.Draw[](drawIds.length);
    for (uint256 index = 0; index < drawIds.length; index++) {
      drawIndex = _drawIdToDrawIndex(drawIds[index]);
      draws[index] = _draws[drawIndex];
    }
    return draws;
  }

  /**
    * @notice External function to create a new draw.
    * @dev    External function to create a new draw from an authorized manager or owner.
    * @param draw Draw struct
    * @return New draw id
  */
  function pushDraw(DrawLib.Draw memory draw) external override onlyManagerOrOwner returns (uint32) {
    return _pushDraw(draw);
  } 

  /**
    * @notice External function to set an existing draw.
    * @dev    External function to set an existing draw from an authorized manager or owner.
    * @param drawIndex Draw index to set
    * @param newDraw   Draw struct
    * @return Draw id
  */
  function setDraw(uint256 drawIndex, DrawLib.Draw memory newDraw) external override onlyManagerOrOwner returns (uint32) {
    return _setDraw(drawIndex, newDraw);
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Internal function to calculate draw index using the draw id.
    * @dev    Use the draw id to calculate the draw index position in the draws ring buffer.
    * @param _drawId Draw id
    * @return Draw index
  */
  function _drawIdToDrawIndex(uint32 _drawId) internal view returns (uint32) {
    uint32 _nextDrawIndex = nextDrawIndex;
    DrawLib.Draw memory _lastDraw;
    // Read the most recently pushed draw in the ring buffer.
    if(_nextDrawIndex == 0) {
      // If nextDrawIndex is 0 the DrawHistory either has NO draws or the ring buffer has looped. Read from the end of the ring buffer if current position is 0.
      _lastDraw = _draws[CARDINALITY - 1];
      // If the draw at the end draws array has no timestamp we can assume no draws have been created.
      require(_lastDraw.timestamp > 0, "DrawHistory/no-draw-history");
    } else {
      _lastDraw = _draws[_nextDrawIndex - 1];
    }
    require(_drawId + CARDINALITY > _lastDraw.drawId, "DrawHistory/draw-expired");
    require(_drawId <= _lastDraw.drawId, "DrawHistory/drawid-out-of-bounds");
    uint256 deltaIndex = _lastDraw.drawId - _drawId;
    return uint32(((_nextDrawIndex - 1) - deltaIndex) % CARDINALITY);
  }

  /**
    * @notice Internal function to create a new draw.
    * @dev    Internal function to create a new draw from an authorized manager or owner.
    * @param _newDraw Draw struct
    * @return New draw id
  */
  function _pushDraw(DrawLib.Draw memory _newDraw) internal returns (uint32) {
    uint32 _nextDrawIndex = nextDrawIndex;
    _draws[_nextDrawIndex] = _newDraw;
    emit DrawSet(_nextDrawIndex, _newDraw.drawId, _newDraw.timestamp, _newDraw.winningRandomNumber);
    nextDrawIndex = (_nextDrawIndex + 1) % CARDINALITY;
    return _newDraw.drawId;
  } 

  /**
    * @notice Internal function to set an existing draw.
    * @dev    Internal function to set an existing draw from an authorized manager or owner.
    * @param _drawIndex Draw index
    * @param _newDraw   Draw struct
    * @return Draw index
  */
  function _setDraw(uint256 _drawIndex, DrawLib.Draw memory _newDraw) internal returns (uint32) {
    _draws[_drawIndex] = _newDraw;
    emit DrawSet(_drawIndex, _newDraw.drawId, _newDraw.timestamp, _newDraw.winningRandomNumber);
    return _newDraw.drawId;
  } 

}