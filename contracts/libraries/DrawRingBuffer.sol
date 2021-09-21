pragma solidity 0.8.6;

import "./RingBuffer.sol";

library DrawRingBuffer {

  struct Buffer {
    uint32 lastDrawId;
    uint32 nextIndex;
    uint32 cardinality;
  }

  function push(Buffer memory _buffer, uint32 _drawId) internal view returns (Buffer memory) {
    // since draws start at 0, we know we are uninitialized if nextIndex = 0 and lastDrawId = 0, since draws montonically increase
    bool bufferNotInitialized = isUninitialized(_buffer);
    require(bufferNotInitialized || _drawId == _buffer.lastDrawId + 1, "DRB/must-be-contig");
    return Buffer({
      lastDrawId: _drawId,
      nextIndex: uint32(RingBuffer.nextIndex(_buffer.nextIndex, _buffer.cardinality)),
      cardinality: _buffer.cardinality
    });
  }

  function getIndex(Buffer memory _buffer, uint32 _drawId) internal view returns (uint32) {
    bool bufferNotInitialized = isUninitialized(_buffer);
    require(!bufferNotInitialized && _drawId <= _buffer.lastDrawId, "DRB/future-draw");
    uint32 indexOffset = _buffer.lastDrawId - _drawId;
    require(indexOffset < _buffer.cardinality, "DRB/expired-draw");
    uint32 mostRecent = uint32(RingBuffer.mostRecentIndex(_buffer.nextIndex, _buffer.cardinality));
    return uint32(RingBuffer.offset(mostRecent, indexOffset, _buffer.cardinality));
  }

  function isUninitialized(Buffer memory _buffer) internal pure returns (bool) {
    // since draws start at 0, we know we are uninitialized if nextIndex = 0 and lastDrawId = 0, since draws montonically increase
    return _buffer.nextIndex == 0 && _buffer.lastDrawId == 0;
  }
} 
