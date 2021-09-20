// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBuffer.sol";

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
  using DrawRingBuffer for DrawRingBuffer.Buffer;

  /**
    * @notice Draws ring buffer length.
    * @dev    Once the number of draws created matches the cardinality, previous draws will be overwritten.
  */
  uint16 public constant MAX_CARDINALITY = 256;

  /**
    * @notice Draws ring buffer array.
  */
  DrawLib.Draw[MAX_CARDINALITY] private _draws;

  /**
   * @notice Holds ring buffer information
   */
  DrawRingBuffer.Buffer internal drawRingBuffer;

  /* ============ Deploy ============ */

  /**
    * @notice Deploy DrawHistory smart contract.
  */
  constructor(uint8 _cardinality) {
    drawRingBuffer.cardinality = _cardinality;
  }

  /* ============ External Functions ============ */

  /**
    * @notice Read all draws.
    * @dev    Return all draws from the draws ring buffer.
    * @return Draws array
  */
  function draws() external view returns(DrawLib.Draw[MAX_CARDINALITY] memory) {
    return _draws;
  }

  /**
    * @notice Read a Draw from the draws ring buffer.
    * @dev    Read a Draw using the Draw.drawId to calculate position in the draws ring buffer.
    * @param drawId Draw.drawId
    * @return DrawLib.Draw
  */
  function getDraw(uint32 drawId) external view override returns(DrawLib.Draw memory) {
    return _draws[_drawIdToDrawIndex(drawRingBuffer, drawId)];
  }

  /**
    * @notice Read multiple Draws from the draws ring buffer.
    * @dev    Read multiple Draws using each Draw.drawId to calculate position in the draws ring buffer.
    * @param drawIds Array of Draw.drawIds
    * @return DrawLib.Draw[]
  */
  function getDraws(uint32[] calldata drawIds) external view override returns(DrawLib.Draw[] memory) {
    DrawLib.Draw[] memory draws = new DrawLib.Draw[](drawIds.length);
    DrawRingBuffer.Buffer memory buffer = drawRingBuffer;
    for (uint256 index = 0; index < drawIds.length; index++) {
      draws[index] = _draws[_drawIdToDrawIndex(buffer, drawIds[index])];
    }
    return draws;
  }

  /**
    * @notice Read newest Draw from the draws ring buffer.
    * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
    * @return DrawLib.Draw
  */
  function getNewestDraw() external view returns (DrawLib.Draw memory) {
    return _getNewestDraw(drawRingBuffer);
  }

  /**
    * @notice Read oldest Draw from the draws ring buffer.
    * @dev    Finds the oldest Draw by comparing and/or diffing totalDraws with the cardinality.
    * @return DrawLib.Draw
  */
  function getOldestDraw() external view returns (DrawLib.Draw memory) {
    // oldest draw should be next available index, otherwise it's at 0
    DrawRingBuffer.Buffer memory buffer = drawRingBuffer;
    DrawLib.Draw memory draw = _draws[buffer.nextIndex];
    if (draw.timestamp == 0) { // if draw is not init, then use draw at 0
      draw = _draws[0];
    }
    return draw;
  }

  /**
    * @notice Push Draw onto draws ring buffer history.
    * @dev    Push new draw onto draws history via authorized manager or owner.
    * @param _draw DrawLib.Draw
    * @return Draw.drawId
  */
  function pushDraw(DrawLib.Draw memory _draw) external override onlyManagerOrOwner returns (uint32) {
    return _pushDraw(_draw);
  }

  /**
    * @notice Set existing Draw in draws ring buffer with new parameters.
    * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.
    * @param _newDraw   DrawLib.Draw
    * @return Draw.drawId
  */
  function setDraw(DrawLib.Draw memory _newDraw) external override onlyOwner returns (uint32) {
    DrawRingBuffer.Buffer memory buffer = drawRingBuffer;
    uint32 index = buffer.getIndex(_newDraw.drawId);
    _draws[index] = _newDraw;
    emit DrawSet(_newDraw.drawId, _newDraw.timestamp, _newDraw.winningRandomNumber);
    return _newDraw.drawId;
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Convert a Draw.drawId to a Draws ring buffer index pointer.
    * @dev    The getNewestDraw.drawId() is used to calculate a Draws ID delta position.
    * @param _drawId Draw.drawId
    * @return Draws ring buffer index pointer
  */
  function _drawIdToDrawIndex(DrawRingBuffer.Buffer memory _buffer, uint32 _drawId) internal view returns (uint32) {
    return _buffer.getIndex(_drawId);
  }

  /**
    * @notice Read newest Draw from the draws ring buffer.
    * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
    * @param _buffer Draw ring buffer
    * @return DrawLib.Draw
  */
  function _getNewestDraw(DrawRingBuffer.Buffer memory _buffer) internal view returns (DrawLib.Draw memory) {
    return _draws[_buffer.getIndex(_buffer.lastDrawId)];
  }

  /**
    * @notice Push Draw onto draws ring buffer history.
    * @dev    Push new draw onto draws history via authorized manager or owner.
    * @param _newDraw DrawLib.Draw
    * @return Draw.drawId
  */
  function _pushDraw(DrawLib.Draw memory _newDraw) internal returns (uint32) {
    DrawRingBuffer.Buffer memory _buffer = drawRingBuffer;
    _draws[_buffer.nextIndex] = _newDraw;
    drawRingBuffer = _buffer.push(_newDraw.drawId);
    emit DrawSet(_newDraw.drawId, _newDraw.timestamp, _newDraw.winningRandomNumber);
    return _newDraw.drawId;
  }

}
