// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@prb/math/contracts/PRBMathSD59x18.sol";

import "../../libraries/VirtualCpmmLib.sol";

contract VirtualCpmmLibHarness {
  using SafeCast for uint256;

  function newCpmm(
    int256 maxSlippage,
    int256 exchangeRate,
    uint256 haveAmount
  ) external pure returns (VirtualCpmmLib.Cpmm memory) {
    return VirtualCpmmLib.newCpmm(
        PRBMath.SD59x18(maxSlippage),
        PRBMath.SD59x18(exchangeRate),
        PRBMathSD59x18Typed.fromInt(haveAmount.toInt256())
    );
  }

  // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
  function getAmountOut(uint amountIn, uint x, uint y) external pure returns (uint amountOut) {
      return VirtualCpmmLib.getAmountOut(amountIn, x, y);
  }

  // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
  function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn) {
      return VirtualCpmmLib.getAmountIn(amountOut, reserveIn, reserveOut);
  }

}
