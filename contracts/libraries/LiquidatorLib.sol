// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./ExtendedSafeCastLib.sol";
import "./CpmmLib.sol";

import "hardhat/console.sol";

/**
 * @title PoolTogether Liquidator Library
 * @author PoolTogether Inc. Team
 * @notice 
 */
library LiquidatorLib {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using ExtendedSafeCastLib for uint256;

    function computeExactAmountIn(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _amountOutB
    ) internal view returns (uint256) {
        require(_amountOutB <= _availableReserveB, "insuff balance");
        (uint256 reserveA, uint256 reserveB) = prepareSwap(_reserveA, _reserveB, _availableReserveB);
        return CpmmLib.getAmountIn(_amountOutB, reserveA, reserveB);
    }

    function computeExactAmountOut(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _amountInA
    ) internal view returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = prepareSwap(_reserveA, _reserveB, _availableReserveB);
        uint256 amountOut = CpmmLib.getAmountOut(_amountInA, reserveA, reserveB);
        require(amountOut <= _availableReserveB, "insuff balance");
        return amountOut;
    }

    function prepareSwap(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        // swap back yield
        uint256 amountInA = CpmmLib.getAmountOut(_availableReserveB, _reserveB, _reserveA);
        reserveA = _reserveA.sub(amountInA);
        reserveB = _reserveB.add(_availableReserveB);
    }

    function _finishSwap(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
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
        uint256 reserveFraction = (_availableReserveB * 1e9) / reserveB;
        uint256 multiplier = (reserveFraction * 1e9) / uint256(_liquidityFraction);
        reserveA = (reserveA*multiplier) / 1e9;
        reserveB = (reserveB*multiplier) / 1e9;
    }

    function swapExactAmountIn(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _amountInA,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal view returns (uint256 reserveA, uint256 reserveB, uint256 amountOut) {
        (reserveA, reserveB) = prepareSwap(_reserveA, _reserveB, _availableReserveB);

        // do swap
        amountOut = CpmmLib.getAmountOut(_amountInA, reserveA, reserveB);
        require(amountOut <= _availableReserveB, "LiqLib/insuff-liq");
        reserveA = reserveA.add(_amountInA);
        reserveB = reserveB.sub(amountOut);

        (reserveA, reserveB) = _finishSwap(reserveA, reserveB, _availableReserveB, amountOut, _swapMultiplier, _liquidityFraction);
    }

    function swapExactAmountOut(
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _availableReserveB,
        uint256 _amountOutB,
        uint32 _swapMultiplier,
        uint32 _liquidityFraction
    ) internal view returns (uint256 reserveA, uint256 reserveB, uint256 amountIn) {
        require(_amountOutB <= _availableReserveB, "LiqLib/insuff-liq");

        (reserveA, reserveB) = prepareSwap(_reserveA, _reserveB, _availableReserveB);

        // do swap
        amountIn = CpmmLib.getAmountIn(_amountOutB, reserveA, reserveB);
        reserveA = reserveA.add(amountIn);
        reserveB = reserveB.sub(_amountOutB);

        (reserveA, reserveB) = _finishSwap(reserveA, reserveB, _availableReserveB, _amountOutB, _swapMultiplier, _liquidityFraction);
    }
}
