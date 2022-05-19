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
        PRBMath.SD59x18 maxSlippage;
        PRBMath.SD59x18 exchangeRate;
        uint256 haveArbTarget;
    }

    function computeExchangeRate(State storage _liquidationState, uint256 availableBalance)
        internal
        view
        returns (PRBMath.SD59x18 memory)
    {
        VirtualCpmmLib.Cpmm memory cpmm = _computeCpmm(_liquidationState, availableBalance);
        return _cpmmToExchangeRate(cpmm);
    }

    function computeExactAmountIn(
        State storage _liquidationState,
        uint256 availableBalance,
        uint256 amountOut
    ) internal pure returns (uint256) {
        require(amountOut <= availableBalance, "insuff balance");
        VirtualCpmmLib.Cpmm memory cpmm = _computeCpmm(
            _liquidationState,
            availableBalance
        );
        return VirtualCpmmLib.getAmountIn(amountOut, cpmm.want, cpmm.have);
    }

    function computeExactAmountOut(
        State storage _liquidationState,
        uint256 availableBalance,
        uint256 amountIn
    ) internal pure returns (uint256) {
        VirtualCpmmLib.Cpmm memory cpmm = _computeCpmm(
            _liquidationState,
            availableBalance
        );
        uint256 amountOut = VirtualCpmmLib.getAmountOut(amountIn, cpmm.want, cpmm.have);
        require(amountOut <= availableBalance, "insuff balance");
        return amountOut;
    }

    function _computeCpmm(
        State storage _liquidationState,
        uint256 availableBalance
    ) internal pure returns (VirtualCpmmLib.Cpmm memory) {
        State memory liquidationState = _liquidationState;
        VirtualCpmmLib.Cpmm memory cpmm = VirtualCpmmLib.newCpmm(
            liquidationState.maxSlippage,
            liquidationState.exchangeRate,
            PRBMathSD59x18Typed.fromInt(liquidationState.haveArbTarget.toInt256())
        );

        // Now we swap available balance for POOL

        uint256 wantAmount = VirtualCpmmLib.getAmountOut(availableBalance, cpmm.have, cpmm.want);

        cpmm.want -= wantAmount;
        cpmm.have += availableBalance;

        return cpmm;
    }

    function swapExactAmountIn(
        State storage liquidationState,
        uint256 availableBalance,
        uint256 amountIn
    ) internal returns (uint256) {
        require(availableBalance > 0, "Whoops! no funds available");
        VirtualCpmmLib.Cpmm memory cpmm = _computeCpmm(
            liquidationState,
            availableBalance
        );

        uint256 amountOut = VirtualCpmmLib.getAmountOut(amountIn, cpmm.want, cpmm.have);
        cpmm.want += amountIn;
        cpmm.have -= amountOut;

        require(amountOut <= availableBalance, "Whoops! have exceeds available");

        liquidationState.exchangeRate = _cpmmToExchangeRate(cpmm);

        return amountOut;
    }

    function swapExactAmountOut(
        State storage liquidationState,
        uint256 availableBalance,
        uint256 amountOut
    ) internal returns (uint256) {
        require(availableBalance > 0, "Whoops! no funds available");
        VirtualCpmmLib.Cpmm memory cpmm = _computeCpmm(
            liquidationState,
            availableBalance
        );

        uint256 amountIn = VirtualCpmmLib.getAmountIn(amountOut, cpmm.want, cpmm.have);
        cpmm.want += amountIn;
        cpmm.have -= amountOut;

        require(amountOut <= availableBalance, "Whoops! have exceeds available");

        liquidationState.exchangeRate = _cpmmToExchangeRate(cpmm);

        return amountIn;
    }

    function _cpmmToExchangeRate(VirtualCpmmLib.Cpmm memory cpmm)
        internal
        pure
        returns (PRBMath.SD59x18 memory)
    {
        return
            PRBMathSD59x18Typed.fromInt(int256(cpmm.have)).div(
                PRBMathSD59x18Typed.fromInt(int256(cpmm.want))
            );
    }
}
