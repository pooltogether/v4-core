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
    int256 maxSlippage,
    uint256 haveArbTarget
  ) external {
    state = LiquidatorLib.State({
      exchangeRate: PRBMath.SD59x18(exchangeRate),
      maxSlippage: PRBMath.SD59x18(maxSlippage),
      haveArbTarget: haveArbTarget
    });
  }

  function computeExchangeRate(uint256 availableBalance) external view returns (int256) {
    return state.computeExchangeRate(availableBalance).value;
  }

  function computeExactAmountIn(uint256 availableBalance, uint256 amountOut) external view returns (uint256) {
    return state.computeExactAmountIn(availableBalance, amountOut);
  }

  function computeExactAmountOut(uint256 availableBalance, uint256 amountIn) external view returns (uint256) {
    return state.computeExactAmountOut(availableBalance, amountIn);
  }

  function swapExactAmountIn(
    uint256 availableBalance,
    uint256 amountIn
  ) external returns (uint256) {
    uint256 result = state.swapExactAmountIn(availableBalance, amountIn);
    emit SwapResult(result);
    return result;
  }

  function swapExactAmountOut(
    uint256 availableBalance,
    uint256 amountOut
  ) external returns (uint256) {
    uint256 result = state.swapExactAmountOut(availableBalance, amountOut);
    emit SwapResult(result);
    return result;
  }
}
