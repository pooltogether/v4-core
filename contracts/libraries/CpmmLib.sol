// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

library CpmmLib {
  using SafeMath for uint256;

  // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
  function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal view returns (uint256 amountOut) {
      require(reserveIn > 0 && reserveOut > 0, "CpmmLib/INSUFF_PAIR_LIQ");
      uint256 numerator = amountIn.mul(reserveOut);
      uint256 denominator = reserveIn.add(amountIn);
      uint256 amountOut = numerator / denominator;
      return amountOut;
  }

  // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
  function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal view returns (uint256 amountIn) {
      // require(amountOut > 0, "CpmmLib: INSUFFICIENT_OUTPUT_AMOUNT");
      require(amountOut < reserveOut, "CpmmLib/INSUFF_LIQ");
      require(reserveIn > 0 && reserveOut > 0, "CpmmLib/INSUFF_PAIR_LIQ");
      uint256 numerator = reserveIn.mul(amountOut);
      uint256 denominator = reserveOut.sub(amountOut);
      amountIn = (numerator / denominator);
  }

}
