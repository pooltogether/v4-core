// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libraries/ExtendedSafeCastLib.sol";
import "./libraries/LiquidatorLib.sol";
import "./interfaces/IPrizePool.sol";
import "./interfaces/IPrizePoolLiquidatorListener.sol";

contract PrizePoolLiquidator {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using ExtendedSafeCastLib for uint256;

  struct LiquidatorConfig {
    address target;
    IERC20 want;
    uint32 swapMultiplier;
    uint32 liquidityFraction;
  }

  struct LiquidatorState {
    uint256 reserveA;
    uint256 reserveB;
  }

  mapping(IPrizePool => LiquidatorConfig) poolLiquidatorConfigs;
  mapping(IPrizePool => LiquidatorState) poolLiquidatorStates;

  IPrizePoolLiquidatorListener public listener;

  function setPrizePool(
    IPrizePool _pool,
    address _target,
    IERC20 _want,
    uint32 _swapMultiplier,
    uint32 _liquidityFraction,
    uint192 _reserveA,
    uint192 _reserveB
  ) external returns (bool) {
    poolLiquidatorConfigs[_pool] = LiquidatorConfig({
      target: _target,
      want: _want,
      swapMultiplier: _swapMultiplier,
      liquidityFraction: _liquidityFraction
    });
    poolLiquidatorStates[_pool] = LiquidatorState({
      reserveA: _reserveA,
      reserveB: _reserveB
    });
    return true;
  }

  function availableBalanceOf(IPrizePool _prizePool) external returns (uint256) {
    return _availableStreamHaveBalance(_prizePool);
  }

  function _availableStreamHaveBalance(IPrizePool _prizePool) internal returns (uint256) {
    return _prizePool.captureAwardBalance();
  }

  function currentExchangeRate(IPrizePool _prizePool) external returns (uint256) {
    LiquidatorState memory state = poolLiquidatorStates[_prizePool];
    (uint256 reserveA, uint256 reserveB) = LiquidatorLib.prepareSwap(
      state.reserveA,
      state.reserveB,
      _availableStreamHaveBalance(_prizePool)
    );
    return (reserveA*1e18) / reserveB;
  }

  function computeExactAmountIn(IPrizePool _prizePool, uint256 _amountOut) external returns (uint256) {
    LiquidatorConfig memory config = poolLiquidatorConfigs[_prizePool];
    LiquidatorState memory state = poolLiquidatorStates[_prizePool];
    return LiquidatorLib.computeExactAmountIn(
      state.reserveA, state.reserveB, _availableStreamHaveBalance(_prizePool), _amountOut, config.swapMultiplier, config.liquidityFraction
    );
  }

  function computeExactAmountOut(IPrizePool _prizePool, uint256 _amountIn) external returns (uint256) {
    LiquidatorConfig memory config = poolLiquidatorConfigs[_prizePool];
    LiquidatorState memory state = poolLiquidatorStates[_prizePool];
    return LiquidatorLib.computeExactAmountOut(
      state.reserveA, state.reserveB, _availableStreamHaveBalance(_prizePool), _amountIn, config.swapMultiplier, config.liquidityFraction
    );
  }

  function swapExactAmountIn(IPrizePool _prizePool, uint256 _amountIn, uint256 _amountOutMin) external returns (uint256) {
    LiquidatorConfig memory config = poolLiquidatorConfigs[_prizePool];
    LiquidatorState memory state = poolLiquidatorStates[_prizePool];
    uint256 availableBalance = _availableStreamHaveBalance(_prizePool);
    (uint256 reserveA, uint256 reserveB, uint256 amountOut) = LiquidatorLib.swapExactAmountIn(
      state.reserveA, state.reserveB,
      availableBalance, _amountIn, config.swapMultiplier, config.liquidityFraction
    );
    state.reserveA = reserveA;
    state.reserveB = reserveB;
    require(amountOut <= availableBalance, "Whoops! have exceeds available");
    require(amountOut >= _amountOutMin, "trade does not meet min");
    poolLiquidatorStates[_prizePool] = state;
    _swap(_prizePool, config.want, config.target, msg.sender, amountOut, _amountIn);
    return amountOut;
  }

  function swapExactAmountOut(IPrizePool _prizePool, uint256 _amountOut, uint256 _amountInMax) external returns (uint256) {
    LiquidatorConfig memory config = poolLiquidatorConfigs[_prizePool];
    LiquidatorState memory state = poolLiquidatorStates[_prizePool];
    uint256 availableBalance = _availableStreamHaveBalance(_prizePool);
    (uint256 reserveA, uint256 reserveB, uint256 amountIn) = LiquidatorLib.swapExactAmountOut(
      state.reserveA, state.reserveB,
      availableBalance, _amountOut, config.swapMultiplier, config.liquidityFraction
    );
    state.reserveA = reserveA;
    state.reserveB = reserveB;
    require(amountIn <= _amountInMax, "trade does not meet min");
    require(_amountOut <= availableBalance, "Whoops! have exceeds available");
    poolLiquidatorStates[_prizePool] = state;
    _swap(_prizePool, config.want, config.target, msg.sender, _amountOut, amountIn);
    return amountIn;
  }

  function _swap(IPrizePool _prizePool, IERC20 _want, address _target, address _account, uint256 _amountOut, uint256 _amountIn) internal {
    _prizePool.award(_account, _amountOut);
    _want.transferFrom(_account, _target, _amountIn);
    IPrizePoolLiquidatorListener _listener = listener;
    if (address(_listener) != address(0)) {
      _listener.afterSwap(_prizePool, _prizePool.getTicket(), _amountOut, _want, _amountIn);
    }
  }

  function getLiquidationState(IPrizePool _prizePool) external view returns (LiquidatorState memory state) {
    return poolLiquidatorStates[_prizePool];
  }
}
