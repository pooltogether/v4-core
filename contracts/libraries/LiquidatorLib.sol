// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./ExtendedSafeCastLib.sol";
import "./CpmmLib.sol";

library LiquidatorLib {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using ExtendedSafeCastLib for uint256;

    function computeExactAmountIn(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableBalance,
        uint256 _amountOut,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal pure returns (uint256) {
        require(_amountOut <= _availableBalance, "insuff balance");
        (uint256 reserveA, uint256 reserveB) = prepareSwap(_reserveA, _reserveB, _availableBalance);
        return CpmmLib.getAmountIn(_amountOut, reserveA, reserveB);
    }

    function computeExactAmountOut(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 availableBalance,
        uint256 amountIn,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal pure returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = prepareSwap(_reserveA, _reserveB, availableBalance);
        uint256 amountOut = CpmmLib.getAmountOut(amountIn, reserveA, reserveB);
        require(amountOut <= availableBalance, "insuff balance");
        return amountOut;
    }

    function prepareSwap(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 availableBalance
    ) internal pure returns (uint256 reserveA, uint256 reserveB) {

        // swap back yield
        uint256 wantAmount = CpmmLib.getAmountOut(availableBalance, _reserveA, _reserveB);
        reserveB = _reserveB.sub(wantAmount);
        reserveA = _reserveA.add(availableBalance);
    }

    function _finishSwap(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableBalance,
        uint256 _reserveBOut,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal view returns (uint256 reserveA, uint256 reserveB) {

        // apply the additional swap
        uint256 extraReserveBOut = (_reserveBOut*_swapMultiplier) / 1e9;
        uint256 extraReserveAIn = CpmmLib.getAmountIn(extraReserveBOut, _reserveA, _reserveB);
        reserveA = _reserveA.add(extraReserveAIn);
        reserveB = _reserveB.sub(extraReserveBOut);

        // now, we want to ensure that the accrued yield is always a small fraction of virtual LP position.
        uint256 multiplier = _availableBalance / (reserveB*_liquidityFraction);
        reserveA = (reserveA*multiplier) / 1e9;
        reserveB = (reserveB*multiplier) / 1e9;
    }

    function swapExactAmountIn(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 availableBalance,
        uint256 amountIn,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal view returns (uint256 reserveA, uint256 reserveB, uint256 amountOut) {
        require(availableBalance > 0, "Whoops! no funds available");

        (reserveA, reserveB) = prepareSwap(_reserveA, _reserveB, availableBalance);

        // do swap
        amountOut = CpmmLib.getAmountOut(amountIn, reserveB, reserveA);
        require(amountOut <= availableBalance, "Whoops! have exceeds available");
        reserveB = reserveB.add(amountIn);
        reserveA = reserveA.sub(amountOut);

        (reserveA, reserveB) = _finishSwap(reserveA, reserveB, availableBalance, amountOut, _swapMultiplier, _liquidityFraction);
    }

    function swapExactAmountOut(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableBalance,
        uint256 _amountOut,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal view returns (uint256 reserveA, uint256 reserveB, uint256 amountIn) {
        require(_availableBalance > 0, "Whoops! no funds available");
        require(_amountOut <= _availableBalance, "Whoops! have exceeds available");

        (reserveA, reserveB) = prepareSwap(_reserveA, _reserveB, _availableBalance);

        // do swap
        amountIn = CpmmLib.getAmountIn(_amountOut, reserveA, reserveB);
        reserveB = reserveB.add(amountIn);
        reserveA = reserveA.sub(_amountOut);

        (reserveA, reserveB) = _finishSwap(reserveA, reserveB, _availableBalance, _amountOut, _swapMultiplier, _liquidityFraction);
    }
}
