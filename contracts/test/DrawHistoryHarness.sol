pragma solidity 0.8.6;

import "../DrawHistory.sol";
import "../libraries/DrawLib.sol";

contract DrawHistoryHarness is DrawHistory {

  constructor(address manager) DrawHistory(manager){
    
  }

  function setNextDrawIndex(uint32 _nextDrawIndex) public returns (uint256) {
    nextDrawIndex = _nextDrawIndex;
    return _nextDrawIndex;
  }

  function bufferPosition(uint256 _nextDrawIndex, uint32 _deltaIndex) external pure returns (uint32) {
    return _bufferPosition(_nextDrawIndex, _deltaIndex);
  }

  function wrapCardinality(uint256 _index) external pure returns (uint32) {
    return _wrapCardinality(_index);
  }

  function setNextDrawIndexAndDraw(
    uint32 nextDrawIndex, 
    uint256 drawIndex, 
    uint32 drawId, 
    uint32 timestamp, 
    uint256 winningRandomNumber
  ) external returns (uint256) {
    setNextDrawIndex(nextDrawIndex);
    DrawLib.Draw memory _draw = DrawLib.Draw({drawId: drawId, timestamp: timestamp, winningRandomNumber: winningRandomNumber});
    _setDraw(drawIndex, _draw);
    return drawIndex;
  }

  function addMultipleDraws(
    uint256 _start, 
    uint256 _numberOfDraws, 
    uint32 _timestamp, 
    uint256 _winningRandomNumber
  ) external returns (uint256) {
    for (uint256 index = _start; index < _numberOfDraws; index++) {
      DrawLib.Draw memory _draw = DrawLib.Draw({drawId: uint32(index), timestamp: _timestamp, winningRandomNumber: _winningRandomNumber});
      _pushDraw(_draw);
    }
  }

}