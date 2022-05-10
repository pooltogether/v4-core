// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@prb/math/contracts/PRBMath.sol";
import "@prb/math/contracts/PRBMathSD59x18Typed.sol";

import "./VirtualCpmmLib.sol";

library LiquidatorLib {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using PRBMathSD59x18Typed for PRBMath.SD59x18;

  struct State {
    PRBMath.SD59x18 exchangeRate;
    uint256 lastSaleTime;
    // positive price range change per second.
    PRBMath.SD59x18 deltaRatePerSecond;
    // Price impact for purchase of accrued funds
    // low slippage => higher frequency arbs, but it tracks the market rate slower (slower to change)
    PRBMath.SD59x18 maxSlippage;
  }

  function _increaseExchangeRateByDeltaTime(
    PRBMath.SD59x18 memory exchangeRate,
    PRBMath.SD59x18 memory deltaRatePerSecond,
    uint256 lastSaleTime,
    uint256 currentTime
  ) internal pure returns (PRBMath.SD59x18 memory) {
    // over time, buying power of POOL goes up.
    PRBMath.SD59x18 memory dt = PRBMathSD59x18Typed.fromInt((currentTime - lastSaleTime).toInt256());
    return exchangeRate.add(
      exchangeRate.mul(dt.mul(deltaRatePerSecond))
    );
  }

  function computeExchangeRate(State storage _liquidationState, uint256 _currentTime) internal view returns (PRBMath.SD59x18 memory) {
    return _increaseExchangeRateByDeltaTime(
        _liquidationState.exchangeRate,
        _liquidationState.deltaRatePerSecond,
        _liquidationState.lastSaleTime,
        _currentTime
    );
  }

  function computeExactAmountInAtTime(State storage _liquidationState, uint256 availableBalance, uint256 amountOut, uint256 currentTime) internal pure returns (uint256) {
    State memory liquidationState = _liquidationState;
    PRBMath.SD59x18 memory newExchangeRate = _increaseExchangeRateByDeltaTime(
        liquidationState.exchangeRate,
        liquidationState.deltaRatePerSecond,
        liquidationState.lastSaleTime,
        currentTime
    );
    if (availableBalance == 0) {
      return 0;
    }
    // console2.log("availableBalance", availableBalance);
    VirtualCpmmLib.Cpmm memory cpmm = VirtualCpmmLib.newCpmm(
      liquidationState.maxSlippage, newExchangeRate, PRBMathSD59x18Typed.fromInt(availableBalance.toInt256())
    );
    return VirtualCpmmLib.getAmountIn(amountOut, cpmm.want, cpmm.have);
  }

  function computeExactAmountOutAtTime(State storage _liquidationState, uint256 availableBalance, uint256 amountIn, uint256 currentTime) internal pure returns (uint256) {
    State memory liquidationState = _liquidationState;
    PRBMath.SD59x18 memory newExchangeRate = _increaseExchangeRateByDeltaTime(
        liquidationState.exchangeRate,
        liquidationState.deltaRatePerSecond,
        liquidationState.lastSaleTime,
        currentTime
    );
    if (availableBalance == 0) {
      return 0;
    }
    VirtualCpmmLib.Cpmm memory cpmm = VirtualCpmmLib.newCpmm(
      liquidationState.maxSlippage, newExchangeRate, PRBMathSD59x18Typed.fromInt(availableBalance.toInt256())
    );
    return VirtualCpmmLib.getAmountOut(amountIn, cpmm.want, cpmm.have);
  }

  function swapExactAmountInAtTime(
    State storage liquidationState,
    uint256 availableBalance,
    uint256 amountIn,
    uint256 currentTime
  ) internal returns (uint256) {
    PRBMath.SD59x18 memory newExchangeRate = _increaseExchangeRateByDeltaTime(
        liquidationState.exchangeRate,
        liquidationState.deltaRatePerSecond,
        liquidationState.lastSaleTime,
        currentTime
    );
    require(availableBalance > 0, "Whoops! no funds available");
    VirtualCpmmLib.Cpmm memory cpmm = VirtualCpmmLib.newCpmm(
      liquidationState.maxSlippage, newExchangeRate, PRBMathSD59x18Typed.fromInt(availableBalance.toInt256())
    );

    uint256 amountOut = VirtualCpmmLib.getAmountOut(amountIn, cpmm.want, cpmm.have);
    cpmm.want += amountIn;
    cpmm.have -= amountOut;

    require(amountOut <= availableBalance, "Whoops! have exceeds available");

    liquidationState.lastSaleTime = currentTime;
    liquidationState.exchangeRate = _cpmmToExchangeRate(cpmm);

    return amountOut;
  }

  function _cpmmToExchangeRate(VirtualCpmmLib.Cpmm memory cpmm) internal pure returns (PRBMath.SD59x18 memory) {
    return PRBMathSD59x18Typed.fromInt(int256(cpmm.have)).div(PRBMathSD59x18Typed.fromInt(int256(cpmm.want)));
  }
}
