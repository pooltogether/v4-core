// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@prb/math/contracts/PRBMath.sol";
import "@prb/math/contracts/PRBMathSD59x18Typed.sol";

import "./libraries/LiquidatorLib.sol";
import "./interfaces/IPrizePool.sol";
import "./interfaces/IPrizePoolLiquidatorListener.sol";

contract PrizePoolLiquidator {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using PRBMathSD59x18Typed for PRBMath.SD59x18;
  using LiquidatorLib for LiquidatorLib.State;

  uint256 time;

  struct Target {
    address target;
    IERC20 want;
  }

  // mapping from prize pool to tokens.
  mapping(IPrizePool => Target) poolTargets;
  mapping(IPrizePool => LiquidatorLib.State) poolLiquidatorStates;

  IPrizePoolLiquidatorListener public listener;

  function setPrizePool(
    IPrizePool pool,
    address target,
    IERC20 want,
    int256 exchangeRate,
    int256 maxSlippage,
    uint256 haveArbTarget
  ) external returns (bool) {
    return setPrizePoolAtTime(pool, target, want, exchangeRate, maxSlippage, haveArbTarget);
  }

  function setPrizePoolAtTime(
    IPrizePool pool,
    address target,
    IERC20 want,
    int256 exchangeRate,
    int256 maxSlippage,
    uint256 haveArbTarget
  ) public returns (bool) {
    poolTargets[pool] = Target({
        target: target,
        want: want
    });
    poolLiquidatorStates[pool] = LiquidatorLib.State({
      exchangeRate: PRBMath.SD59x18(exchangeRate),
      maxSlippage: PRBMath.SD59x18(maxSlippage),
      haveArbTarget: haveArbTarget
    });
    return true;
  }

  function setPrizePoolLiquidationState(IPrizePool _prizePool, int256 maxSlippage) external {
    poolLiquidatorStates[_prizePool].maxSlippage = PRBMath.SD59x18(maxSlippage);
  }

  function availableBalanceOf(IPrizePool _prizePool) external returns (uint256) {
    return _availableStreamHaveBalance(_prizePool);
  }

  function _availableStreamHaveBalance(IPrizePool _prizePool) internal returns (uint256) {
    return _prizePool.captureAwardBalance();
  }

  function setTime(uint256 _time) external {
    time = _time;
  }

  function currentExchangeRate(IPrizePool _prizePool) external returns (int256) {
    return poolLiquidatorStates[_prizePool].computeExchangeRate(_availableStreamHaveBalance(_prizePool)).toInt();
  }

  function computeExactAmountIn(IPrizePool _prizePool, uint256 amountOut) external returns (uint256) {
    return poolLiquidatorStates[_prizePool].computeExactAmountIn(_availableStreamHaveBalance(_prizePool), amountOut);
  }

  function computeExactAmountOut(IPrizePool _prizePool, uint256 amountIn) external returns (uint256) {
    return poolLiquidatorStates[_prizePool].computeExactAmountOut(_availableStreamHaveBalance(_prizePool), amountIn);
  }

  function swapExactAmountIn(IPrizePool _prizePool, uint256 amountIn, uint256 amountOutMin) external returns (uint256) {
    return _swapExactAmountIn(_prizePool, amountIn, amountOutMin);
  }

  function _swapExactAmountIn(IPrizePool _prizePool, uint256 amountIn, uint256 amountOutMin) internal returns (uint256) {
    uint256 availableBalance = _availableStreamHaveBalance(_prizePool);
    uint256 amountOut = poolLiquidatorStates[_prizePool].swapExactAmountIn(
      availableBalance, amountIn
    );

    require(amountOut <= availableBalance, "Whoops! have exceeds available");
    require(amountOut >= amountOutMin, "trade does not meet min");

    _swap(_prizePool, msg.sender, amountOut, amountIn);

    return amountOut;
  }

  function swapExactAmountOut(IPrizePool _prizePool, uint256 amountOut, uint256 amountInMax) external returns (uint256) {
    return _swapExactAmountOut(_prizePool, amountOut, amountInMax);
  }

  function _swapExactAmountOut(
    IPrizePool _prizePool,
    uint256 amountOut,
    uint256 amountInMax
  ) internal returns (uint256) {
    uint256 availableBalance = _availableStreamHaveBalance(_prizePool);
    uint256 amountIn = poolLiquidatorStates[_prizePool].swapExactAmountOut(
      availableBalance, amountOut
    );

    require(amountIn <= amountInMax, "trade does not meet min");
    require(amountOut <= availableBalance, "Whoops! have exceeds available");

    _swap(_prizePool, msg.sender, amountOut, amountIn);

    return amountIn;
  }

  function _swap(IPrizePool _prizePool, address _account, uint256 _amountOut, uint256 _amountIn) internal {
    Target storage target = poolTargets[_prizePool];
    IERC20 want = target.want;
    _prizePool.award(_account, _amountOut);
    want.transferFrom(_account, target.target, _amountIn);
    IPrizePoolLiquidatorListener _listener = listener;
    if (address(_listener) != address(0)) {
      _listener.afterSwap(_prizePool, _prizePool.getTicket(), _amountOut, want, _amountIn);
    }
  }

  function getLiquidationState(IPrizePool _prizePool) external view returns (
    int exchangeRate
  ) {
    LiquidatorLib.State memory state = poolLiquidatorStates[_prizePool];
    exchangeRate = state.exchangeRate.value;
  }
}
