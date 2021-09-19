// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";

/**
  * @title  PoolTogether V4 DrawHistory
  * @author PoolTogether Inc Team
  * @notice The DrawHistory keeps a historical record of Draws created/pushed by DrawBeacon(s).
            Once a DrawBeacon (on mainnet) completes a RNG request, a new Draw will be added
            to the DrawHistory draws ring buffer. A DrawHistory will store a limited number
            of Draws before beginning to overwrite (managed via the cardinality) previous Draws.
            All mainnet DrawHistory(s) are updated directly from a DrawBeacon, but non-mainnet 
            DrawHistory(s) (Matic, Optimism, Arbitrum, etc...) will receive a cross-chain message,
            duplicating the mainnet Draw configuration - enabling a prize savings liquidity network.
*/
contract DrawHistory is IDrawHistory, OwnerOrManager {

  /**
    * @notice Next index position for a new Draw in the _draws ring buffer.
  */
  uint32 public nextDrawIndex;

   /**
    * @notice Total draws pushed to DrawHistory.
  */
  uint32 public totalDraws;

  /**
    * @notice Draws ring buffer length.
    * @dev    Once the number of draws created matches the cardinality, previous draws will be overwritten.
  */
  uint16 public constant CARDINALITY = 256;

  /**
    * @notice Draws ring buffer array.
  */
  DrawLib.Draw[CARDINALITY] private _draws;

  /* ============ Deploy ============ */

  /**
    * @notice Deploy DrawHistory smart contract.
  */
  constructor() {}

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
    * @notice Convert a Draw.drawId to a Draws ring buffer index pointer. 
    * @dev    The getNewestDraw.drawId() is used to calculate a Draws ID delta position.
    * @param drawId Draw.drawId
    * @return Draws ring buffer index pointer
  */
  function drawIdToDrawIndex(uint32 drawId) external view override returns(uint32) {
    return _drawIdToDrawIndex(drawId);
  }

  /**
    * @notice Read a Draw from the draws ring buffer.
    * @dev    Read a Draw using the Draw.drawId to calculate position in the draws ring buffer.
    * @param drawId Draw.drawId
    * @return DrawLib.Draw
  */
  function getDraw(uint32 drawId) external view override returns(DrawLib.Draw memory) {
    uint32 drawIndex = _drawIdToDrawIndex(drawId);
    return _draws[drawIndex];
  }

  /**
    * @notice Read multiple Draws from the draws ring buffer.
    * @dev    Read multiple Draws using each Draw.drawId to calculate position in the draws ring buffer.
    * @param drawIds Array of Draw.drawIds
    * @return DrawLib.Draw[]
  */
  function getDraws(uint32[] calldata drawIds) external view override returns(DrawLib.Draw[] memory) {
    DrawLib.Draw[] memory draws = new DrawLib.Draw[](drawIds.length);
    for (uint256 index = 0; index < drawIds.length; index++) {
      draws[index] = _draws[_drawIdToDrawIndex(drawIds[index])];
    }
    return draws;
  }

  /**
    * @notice Read newest Draw from the draws ring buffer.
    * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
    * @return DrawLib.Draw
  */
  function getNewestDraw() external view returns (DrawLib.Draw memory) {
    return _getNewestDraw(nextDrawIndex);
  }

  /**
    * @notice Read oldest Draw from the draws ring buffer.
    * @dev    Finds the oldest Draw by comparing and/or diffing totalDraws with the cardinality.
    * @return DrawLib.Draw
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
    * @notice Push Draw onto draws ring buffer history.
    * @dev    Push new draw onto draws history via authorized manager or owner.
    * @param draw DrawLib.Draw
    * @return Draw.drawId
  */
  function pushDraw(DrawLib.Draw memory draw) external override onlyManagerOrOwner returns (uint32) {
    return _pushDraw(draw);
  }

  /**
    * @notice Set existing Draw in draws ring buffer with new parameters.
    * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.  
    * @param drawIndex Ring buffer index (use drawIdToDrawIndex to calculate the correct draw index)
    * @param newDraw   DrawLib.Draw
    * @return Draw.drawId
  */
  function setDraw(uint256 drawIndex, DrawLib.Draw memory newDraw) external override onlyOwner returns (uint32) {
    return _setDraw(drawIndex, newDraw);
  }

  /* ============ Pure Functions ============ */

  /**
    * @dev    Calculates a ring buffer position using the next index and a Draws delta index
    * @param _nextBufferIndex Next available ring buffer slot
    * @param _deltaIndex      Delta index (difference between a Draw.drawId and newestDraw.drawId)
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
    * @notice Convert a Draw.drawId to a Draws ring buffer index pointer. 
    * @dev    The getNewestDraw.drawId() is used to calculate a Draws ID delta position.
    * @param _drawId Draw.drawId
    * @return Draws ring buffer index pointer
  */
  function _drawIdToDrawIndex(uint32 _drawId) internal view returns (uint32) {
    uint32 _nextDrawIndex = nextDrawIndex;
    DrawLib.Draw memory _newestDraw = _getNewestDraw(_nextDrawIndex);
    require(_drawId + CARDINALITY > _newestDraw.drawId, "DrawHistory/draw-expired");
    require(_drawId <= _newestDraw.drawId, "DrawHistory/drawid-out-of-bounds");
    uint256 _deltaIndex = _newestDraw.drawId - _drawId;
    return _bufferPosition(_nextDrawIndex, uint32(_deltaIndex));
  }

  /**
    * @notice Read newest Draw from the draws ring buffer.
    * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
    * @param _nextDrawIndex Next draws ring buffer slot
    * @return DrawLib.Draw
  */
  function _getNewestDraw(uint256 _nextDrawIndex) internal view returns (DrawLib.Draw memory) {
    return _draws[_wrapCardinality((_nextDrawIndex + CARDINALITY) - 1)];
  }

  /**
    * @notice Push Draw onto draws ring buffer history.
    * @dev    Push new draw onto draws history via authorized manager or owner.
    * @param _newDraw DrawLib.Draw
    * @return Draw.drawId
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
    * @notice Set existing Draw in draws ring buffer with new parameters.
    * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.  
    * @param _drawIndex Ring buffer index (use drawIdToDrawIndex to calculate the correct draw index)
    * @param _newDraw   DrawLib.Draw
    * @return Draw.drawId
  */
  function _setDraw(uint256 _drawIndex, DrawLib.Draw memory _newDraw) internal returns (uint32) {
    _draws[_drawIndex] = _newDraw;
    emit DrawSet(_drawIndex, _newDraw.drawId, _newDraw.timestamp, _newDraw.winningRandomNumber);
    return _newDraw.drawId;
  }

}
