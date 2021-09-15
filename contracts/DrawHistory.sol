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
    * @notice Total draws pushed to the draw history.
  */
  uint32 public totalDraws;

  /**
    * @notice Ring buffer array size.
  */
  uint16 public constant CARDINALITY = 256;

  /**
    * @notice Draws ring buffer array.
  */
  DrawLib.Draw[CARDINALITY] private _draws;

  /* ============ Initialize ============ */

  /**
    * @notice Initialize DrawHistory smart contract.
    *
    * @param _manager Draw manager address
  */
  constructor(
    address _manager
  ) public {
    
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
  function drawIdToDrawIndex(uint32 drawId) external view override returns(uint32) {
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
    DrawLib.Draw[] memory draws = new DrawLib.Draw[](drawIds.length);
    for (uint256 index = 0; index < drawIds.length; index++) {
      draws[index] = _draws[_drawIdToDrawIndex(drawIds[index])];
    }
    return draws;
  }

  /**
    * @notice External function to get the newest draw.
    * @dev    External function to get the newest draw using the nextDrawIndex.
    * @return Newest draw
  */
  function getNewestDraw() external view returns (DrawLib.Draw memory) {
    return _getNewestDraw(nextDrawIndex);
  }

  /**
    * @notice Function to get the oldest draw.
    * @dev    Function to get the oldest draw using the totalDraws.
    * @return Last draw
  */
  function getOldestDraw() external view returns (DrawLib.Draw memory) {
    uint256 _totalDraws = totalDraws;
    uint256 _nextDrawIndex = nextDrawIndex;
    if(_totalDraws < CARDINALITY) {
      return _draws[_nextDrawIndex - _totalDraws];
    } else {
      return _draws[(_totalDraws - CARDINALITY) % CARDINALITY];
    }
  }

  /**
    * @notice Push new draw onto draws history.
    * @dev    Push new draw onto draws history via authorized manager or owner.
    * @param draw Draw struct
    * @return New draw id
  */
  function pushDraw(DrawLib.Draw memory draw) external override onlyManagerOrOwner returns (uint32) {
    return _pushDraw(draw);
  } 

  /**
    * @notice Set existing draw in draw history.
    * @dev    Set existing draw in draw history via the owner.
    * @param drawIndex Draw index to set
    * @param newDraw   Draw struct
    * @return Draw id
  */
  function setDraw(uint256 drawIndex, DrawLib.Draw memory newDraw) external override onlyOwner returns (uint32) {
    return _setDraw(drawIndex, newDraw);
  }

  /* ============ Pure Functions ============ */

  /**
    * @dev    Calculates a ring buffer position using the next index and delta index
    * @param _nextBufferIndex Next ring buffer index 
    * @param _deltaIndex Delta index 
    * @return Ring buffer index pointer
  */
  function _bufferPosition(uint256 _nextBufferIndex, uint32 _deltaIndex) internal pure returns (uint32) {
    return _wrapCardinality(((_nextBufferIndex + CARDINALITY) - 1) - _deltaIndex);
  }

  /**
    * @dev    Modulo index with ring buffer cardinality.
    * @param _index Ring buffer index 
    * @return Ring buffer index pointer
  */
  function _wrapCardinality(uint256 _index) internal pure returns (uint32) {
    return uint32(_index % CARDINALITY);
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
    DrawLib.Draw memory _lastDraw = _getNewestDraw(_nextDrawIndex);
    require(_drawId + CARDINALITY > _lastDraw.drawId, "DrawHistory/draw-expired");
    require(_drawId <= _lastDraw.drawId, "DrawHistory/drawid-out-of-bounds");
    uint256 _deltaIndex = _lastDraw.drawId - _drawId;
    return _bufferPosition(_nextDrawIndex, uint32(_deltaIndex));
  }

  /**
    * @notice Internal function to get the last draw.
    * @dev    Internal function to get the last draw using the nextDrawIndex.
    * @return Last draw
  */
  function _getNewestDraw(uint256 _nextDrawIndex) internal view returns (DrawLib.Draw memory) {
    return _draws[_wrapCardinality((_nextDrawIndex + CARDINALITY) - 1)];
  }

  /**
    * @notice Internal function to create a new draw.
    * @dev    Internal function to create a new draw from an authorized manager or owner.
    * @param _newDraw Draw struct
    * @return New draw id
  */
  function _pushDraw(DrawLib.Draw memory _newDraw) internal returns (uint32) {
    uint32 _nextDrawIndex = nextDrawIndex;
    DrawLib.Draw memory _newestDraw = _getNewestDraw(_nextDrawIndex);
    if (_newestDraw.timestamp != 0) {
      require(_newDraw.drawId == _newestDraw.drawId + 1, "DrawHistory/nonsequential-draw");
    }
    _draws[_nextDrawIndex] = _newDraw;
    emit DrawSet(_nextDrawIndex, _newDraw.drawId, _newDraw.timestamp, _newDraw.winningRandomNumber);
    nextDrawIndex = _wrapCardinality(_nextDrawIndex + 1);
    totalDraws += 1;
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