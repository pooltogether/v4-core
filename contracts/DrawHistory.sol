// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBufferLib.sol";

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
contract DrawHistory is IDrawHistory, Manageable {
  using DrawRingBufferLib for DrawRingBufferLib.Buffer;

  /// @notice Draws ring buffer max length.
  uint16 public constant MAX_CARDINALITY = 256;

  /// @notice Draws ring buffer array.
  DrawLib.Draw[MAX_CARDINALITY] internal _draws;

  /// @notice Holds ring buffer information
  DrawRingBufferLib.Buffer internal drawRingBuffer;

  /* ============ Deploy ============ */

  /**
    * @notice Deploy DrawHistory smart contract.
    * @param _owner Address of the owner of the DrawHistory.
    * @param _cardinality Draw ring buffer cardinality.
  */
  constructor(
    address _owner,
    uint8 _cardinality
  ) Ownable(_owner) {
    drawRingBuffer.cardinality = _cardinality;
  }

  /* ============ External Functions ============ */

  /// @inheritdoc IDrawHistory
  function getDraw(uint32 drawId) external view override returns(DrawLib.Draw memory) {
    return _draws[_drawIdToDrawIndex(drawRingBuffer, drawId)];
  }

  /// @inheritdoc IDrawHistory
  function getDraws(uint32[] calldata drawIds) external view override returns(DrawLib.Draw[] memory) {
    DrawLib.Draw[] memory draws = new DrawLib.Draw[](drawIds.length);
    DrawRingBufferLib.Buffer memory buffer = drawRingBuffer;
    for (uint256 index = 0; index < drawIds.length; index++) {
      draws[index] = _draws[_drawIdToDrawIndex(buffer, drawIds[index])];
    }
    return draws;
  }

  /// @inheritdoc IDrawHistory
  function getNewestDraw() external view override returns (DrawLib.Draw memory) {
    return _getNewestDraw(drawRingBuffer);
  }

  /// @inheritdoc IDrawHistory
  function getOldestDraw() external view override returns (DrawLib.Draw memory) {
    DrawRingBufferLib.Buffer memory buffer = drawRingBuffer;
    DrawLib.Draw memory draw = _draws[buffer.nextIndex];
    
    // IF the draw.timestamp is 0 the ring buffer HAS NOT reached he end.
    // Thus Draw a index 0 is the oldest draw.
    if (draw.timestamp == 0) {
      draw = _draws[0];
    }
    return draw;
  }

  /// @inheritdoc IDrawHistory
  function pushDraw(DrawLib.Draw memory _draw) external override onlyManagerOrOwner returns (uint32) {
    return _pushDraw(_draw);
  }

  /// @inheritdoc IDrawHistory
  function setDraw(DrawLib.Draw memory _newDraw) external override onlyOwner returns (uint32) {
    DrawRingBufferLib.Buffer memory buffer = drawRingBuffer;
    uint32 index = buffer.getIndex(_newDraw.drawId);
    _draws[index] = _newDraw;
    emit DrawSet(_newDraw.drawId, _newDraw);
    return _newDraw.drawId;
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Convert a Draw.drawId to a Draws ring buffer index pointer.
    * @dev    The getNewestDraw.drawId() is used to calculate a Draws ID delta position.
    * @param _drawId Draw.drawId
    * @return Draws ring buffer index pointer
  */
  function _drawIdToDrawIndex(DrawRingBufferLib.Buffer memory _buffer, uint32 _drawId) internal pure returns (uint32) {
    return _buffer.getIndex(_drawId);
  }

  /**
    * @notice Read newest Draw from the draws ring buffer.
    * @dev    Uses the lastDrawId to calculate the most recently added Draw.
    * @param _buffer Draw ring buffer
    * @return DrawLib.Draw
  */
  function _getNewestDraw(DrawRingBufferLib.Buffer memory _buffer) internal view returns (DrawLib.Draw memory) {
    return _draws[_buffer.getIndex(_buffer.lastDrawId)];
  }

  /**
    * @notice Push Draw onto draws ring buffer history.
    * @dev    Push new draw onto draws list via authorized manager or owner.
    * @param _newDraw DrawLib.Draw
    * @return Draw.drawId
  */
  function _pushDraw(DrawLib.Draw memory _newDraw) internal returns (uint32) {
    DrawRingBufferLib.Buffer memory _buffer = drawRingBuffer;
    _draws[_buffer.nextIndex] = _newDraw;
    drawRingBuffer = _buffer.push(_newDraw.drawId);
    emit DrawSet(_newDraw.drawId, _newDraw);
    return _newDraw.drawId;
  }

}
