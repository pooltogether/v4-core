// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../PrizePoolLiquidator.sol";

contract PrizePoolLiquidatorHarness is PrizePoolLiquidator {

  function swapExactAmountInAtTime(IPrizePool _prizePool, uint256 amountIn, uint256 amountOutMin, uint256 currentTime) external returns (uint256) {
    return _swapExactAmountInAtTime(_prizePool, amountIn, amountOutMin, currentTime);
  }

  function swapExactAmountOutAtTime(
    IPrizePool _prizePool,
    uint256 amountOut,
    uint256 amountInMax,
    uint256 currentTime
  ) external returns (uint256) {
    return _swapExactAmountOutAtTime(_prizePool, amountOut, amountInMax, currentTime);
  }
}
