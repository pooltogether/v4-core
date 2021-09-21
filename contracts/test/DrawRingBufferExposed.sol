// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "../libraries/DrawRingBuffer.sol";

/**
  * @title  Expose the DrawRingBufferLibrary for unit tests
  * @author PoolTogether Inc.
 */
contract DrawRingBufferLibExposed {
  using DrawRingBuffer for DrawRingBuffer.Buffer;


  uint16 public constant MAX_CARDINALITY = 256;
  DrawRingBuffer.Buffer internal drawRingBuffer;

  constructor(uint8 _cardinality) {
    drawRingBuffer.cardinality = _cardinality;
  }

  function _push(DrawRingBuffer.Buffer memory _buffer, uint32 _drawId) external view returns (DrawRingBuffer.Buffer memory) {
    return DrawRingBuffer.push(_buffer, _drawId);
  }

  function _getIndex(DrawRingBuffer.Buffer memory _buffer, uint32 _drawId) external view returns (uint32) {
    return DrawRingBuffer.getIndex(_buffer, _drawId);
  }
  
  function _isUninitialized(DrawRingBuffer.Buffer memory _buffer) external view returns (bool) {
    return DrawRingBuffer.isUninitialized(_buffer);
  }

}
