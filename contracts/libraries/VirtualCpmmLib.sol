// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@prb/math/contracts/PRBMathSD59x18Typed.sol";

library VirtualCpmmLib {
  using SafeCast for uint256;
  using SafeMath for uint256;
  using PRBMathSD59x18Typed for PRBMath.SD59x18;

  struct Cpmm {
    uint256 have;
    uint256 want;
  }

  function newCpmm(
    PRBMath.SD59x18 memory maxSlippage,
    PRBMath.SD59x18 memory exchangeRate,
    PRBMath.SD59x18 memory haveAmount
  ) internal pure returns (Cpmm memory) {
    // x = (b / (0.99 * ex)) / (b*ex/(b*0.99*ex) - 1)
    PRBMath.SD59x18 memory one = PRBMath.SD59x18(1 ether);
    PRBMath.SD59x18 memory slipEx = one.sub(maxSlippage).mul(exchangeRate);
    PRBMath.SD59x18 memory want = haveAmount.div(slipEx).div(
      haveAmount.mul(exchangeRate).div(haveAmount.mul(slipEx)).sub(one)
    );
    PRBMath.SD59x18 memory have = want.mul(exchangeRate);
    return Cpmm({
        have: uint256(have.toInt()),
        want: uint256(want.toInt())
    });
  }

  // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
  function getAmountOut(uint amountIn, uint x, uint y) internal pure returns (uint amountOut) {
      // require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
      require(x > 0 && y > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
      uint numerator = amountIn.mul(y);
      uint denominator = x.add(amountIn);
      return numerator / denominator;
  }

  // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
  function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
      // require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
      require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
      uint numerator = reserveIn.mul(amountOut);
      uint denominator = reserveOut.sub(amountOut);
      amountIn = (numerator / denominator);
  }

}
