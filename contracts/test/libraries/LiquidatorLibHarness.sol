// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../libraries/LiquidatorLib.sol";

contract LiquidatorLibHarness {
  using SafeMath for uint256;
  using SafeCast for uint256;

  function prepareSwap(
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _availableReserveB
  ) external view returns (uint256 reserveA, uint256 reserveB) {
    return LiquidatorLib.prepareSwap(_reserveA, _reserveB, _availableReserveB);
  }

  function computeExactAmountIn(
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _availableReserveB,
    uint256 _amountOutB
  ) external view returns (uint256) {
    return LiquidatorLib.computeExactAmountIn(_reserveA, _reserveB, _availableReserveB, _amountOutB);
  }

  function computeExactAmountOut(
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _availableReserveB,
    uint256 _amountInA
  ) external view returns (uint256) {
    return LiquidatorLib.computeExactAmountOut(_reserveA, _reserveB, _availableReserveB, _amountInA);
  }

  function swapExactAmountIn(
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _availableReserveB,
    uint256 _amountInA,
    uint32 _swapMultiplier,
    uint32 _liquidityFraction
  ) external view returns (uint256 reserveA, uint256 reserveB, uint256 amountOut) {
    return LiquidatorLib.swapExactAmountIn(_reserveA, _reserveB, _availableReserveB, _amountInA, _swapMultiplier, _liquidityFraction);
  }

  function swapExactAmountOut(
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _availableReserveB,
    uint256 _amountOutB,
    uint32 _swapMultiplier,
    uint32 _liquidityFraction
  ) external view returns (uint256 reserveA, uint256 reserveB, uint256 amountIn) {
    return LiquidatorLib.swapExactAmountOut(_reserveA, _reserveB, _availableReserveB, _amountOutB, _swapMultiplier, _liquidityFraction);
  }
}
