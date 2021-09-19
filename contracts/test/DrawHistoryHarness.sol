pragma solidity 0.8.6;

import "../DrawHistory.sol";
import "../libraries/DrawLib.sol";

contract DrawHistoryHarness is DrawHistory {

  constructor(uint8 card) DrawHistory(card) {
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
