// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../libraries/CpmmLib.sol";

contract CpmmLibHarness {

  // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
  function getAmountOut(uint amountIn, uint x, uint y) external view returns (uint amountOut) {
      return CpmmLib.getAmountOut(amountIn, x, y);
  }

  // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
  function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external view returns (uint amountIn) {
      return CpmmLib.getAmountIn(amountOut, reserveIn, reserveOut);
  }

}
