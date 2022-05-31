// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../libraries/LiquidatorLib.sol";

contract LiquidatorLibHarness {
  using LiquidatorLib for LiquidatorLib.State;
  using SafeMath for uint256;
  using SafeCast for uint256;
  using PRBMathSD59x18Typed for PRBMath.SD59x18;

  LiquidatorLib.State public state;

  event SwapResult(
    uint256 amount
  );

  function setState(
    int256 exchangeRate,
    uint256 lastSaleTime,
    int256 deltaRatePerSecond,
    int256 maxSlippage
  ) external {
    state = LiquidatorLib.State({
      exchangeRate: PRBMath.SD59x18(exchangeRate),
      lastSaleTime: lastSaleTime,
      deltaRatePerSecond: PRBMath.SD59x18(deltaRatePerSecond),
      maxSlippage: PRBMath.SD59x18(maxSlippage)
    });
  }

  function computeExchangeRate(uint256 _currentTime) external view returns (int256) {
    return state.computeExchangeRate(_currentTime).value;
  }

  function computeExactAmountInAtTime(uint256 availableBalance, uint256 amountOut, uint256 currentTime) external view returns (uint256) {
    return state.computeExactAmountInAtTime(availableBalance, amountOut, currentTime);
  }

  function computeExactAmountOutAtTime(uint256 availableBalance, uint256 amountIn, uint256 currentTime) external view returns (uint256) {
    return state.computeExactAmountOutAtTime(availableBalance, amountIn, currentTime);
  }

  function swapExactAmountInAtTime(
    uint256 availableBalance,
    uint256 amountIn,
    uint256 currentTime
  ) external returns (uint256) {
    uint256 result = state.swapExactAmountInAtTime(availableBalance, amountIn, currentTime);
    emit SwapResult(result);
    return result;
  }

  function swapExactAmountOutAtTime(
    uint256 availableBalance,
    uint256 amountOut,
    uint256 currentTime
  ) external returns (uint256) {
    uint256 result = state.swapExactAmountOutAtTime(availableBalance, amountOut, currentTime);
    emit SwapResult(result);
    return result;
  }
}
