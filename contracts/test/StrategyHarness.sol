// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../TsunamiPrizeStrategy.sol";

contract StrategyHarness is TsunamiPrizeStrategy {

  Draw internal globalDraw;

  function setDraw(Draw calldata _draw) external {
    globalDraw = _draw;
  }
  
  function setDrawId(uint256 _drawId) external {
    currentDrawId = _drawId;
  }

  function claimIt(address user, uint256[] calldata timestamps, uint256[] calldata balances, bytes calldata data) external {
    _claim(user, timestamps, balances, data);
  }

  function _encodeData(uint256[][] calldata data) external {
    
  }

  function _findDraw(uint256 timestamp) override internal returns (Draw memory draw, uint256 drawId) {
    return (globalDraw, 0);
  }
}
