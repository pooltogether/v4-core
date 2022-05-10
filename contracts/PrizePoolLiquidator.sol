// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@prb/math/contracts/PRBMath.sol";
import "@prb/math/contracts/PRBMathSD59x18Typed.sol";

import "./libraries/LiquidatorLib.sol";

contract PrizePoolLiquidator {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using PRBMathSD59x18Typed for PRBMath.SD59x18;
  using LiquidatorLib for LiquidatorLib.State;

  uint256 time;

  struct Stream {
    address source;
    IERC20 have;
    address target;
    IERC20 want;
  }

  Stream[] public streams;
  mapping(uint256 => LiquidatorLib.State) liquidatorStates;

  function addStream(
    address source,
    address target,
    IERC20 have,
    IERC20 want,
    int256 exchangeRate,
    int256 deltaRatePerSecond,
    int256 maxSlippage
  ) external returns (uint256) {
    return addStreamAtTime(source, target, have, want, exchangeRate, deltaRatePerSecond, maxSlippage, block.timestamp);
  }

  function addStreamAtTime(
    address source,
    address target,
    IERC20 have,
    IERC20 want,
    int256 exchangeRate,
    int256 deltaRatePerSecond,
    int256 maxSlippage,
    uint256 currentTime
  ) public returns (uint256) {
    streams.push(
      Stream({
        source: source,
        target: target,
        have: have,
        want: want
      })
    );
    uint256 streamId = streams.length - 1;
    liquidatorStates[streamId] = LiquidatorLib.State({
      exchangeRate: PRBMath.SD59x18(exchangeRate),
      lastSaleTime: currentTime,
      // positive price range change per second.
      deltaRatePerSecond: PRBMath.SD59x18(deltaRatePerSecond),
      // Price impact for purchase of accrued funds
      // low slippage => higher frequency arbs, but it tracks the market rate slower (slower to change)
      maxSlippage: PRBMath.SD59x18(maxSlippage)
    });
    return streamId;
  }

  function setStream(uint256 streamId, int256 deltaRatePerSecond, int256 maxSlippage) external {
    liquidatorStates[streamId].deltaRatePerSecond = PRBMath.SD59x18(deltaRatePerSecond);
    liquidatorStates[streamId].maxSlippage = PRBMath.SD59x18(maxSlippage);
  }

  function numberOfStreams() external view returns (uint256) {
    return streams.length;
  }

  function balanceOf(uint256 streamId) external view returns (uint256) {
    Stream storage stream = streams[streamId];
    return stream.have.balanceOf(stream.source);
  }

  function _availableStreamHaveBalance(Stream storage _stream) internal virtual returns (uint256) {
    return _stream.have.balanceOf(_stream.source);
  }

  function _streamTransferHave(Stream storage _stream, address _to, uint256 _amount) internal virtual {
    _stream.have.transferFrom(_stream.source, _to, _amount);
  }

  function availableBalanceOf(uint256 streamId) external returns (uint256) {
    return _availableStreamHaveBalance(streams[streamId]);
  }

  function setTime(uint256 _time) external {
    time = _time;
  }

  function currentExchangeRate(uint256 streamId) external view returns (int256) {
    return liquidatorStates[streamId].computeExchangeRate(block.timestamp).toInt();
  }

  function computeExactAmountIn(uint256 streamId, uint256 amountOut) external returns (uint256) {
    return liquidatorStates[streamId].computeExactAmountInAtTime(_availableStreamHaveBalance(streams[streamId]), amountOut, block.timestamp);
  }

  function computeExactAmountInAtTime(uint256 streamId, uint256 amountOut, uint256 currentTime) public returns (uint256) {
    return liquidatorStates[streamId].computeExactAmountInAtTime(_availableStreamHaveBalance(streams[streamId]), amountOut, currentTime);
  }

  function computeExactAmountOut(uint256 streamId, uint256 amountIn) public returns (uint256) {
    return liquidatorStates[streamId].computeExactAmountOutAtTime(_availableStreamHaveBalance(streams[streamId]), amountIn, block.timestamp);
  }

  function computeExactAmountOutAtTime(uint256 streamId, uint256 amountIn, uint256 currentTime) public returns (uint256) {
    return liquidatorStates[streamId].computeExactAmountOutAtTime(_availableStreamHaveBalance(streams[streamId]), amountIn, currentTime);
  }

  function swapExactAmountIn(uint256 streamId, uint256 amountIn) public returns (uint256) {
    return swapExactAmountInAtTime(streamId, amountIn, block.timestamp);
  }

  function swapExactAmountInAtTime(uint256 streamId, uint256 amountIn, uint256 currentTime) public returns (uint256) {
    uint256 availableBalance = _availableStreamHaveBalance(streams[streamId]);
    uint256 amountOut = liquidatorStates[streamId].swapExactAmountInAtTime(
      availableBalance, amountIn, currentTime
    );

    Stream storage stream = streams[streamId];

    require(amountOut <= availableBalance, "Whoops! have exceeds available");

    if (stream.source == address(this)) {
      stream.have.transfer(msg.sender, amountOut);
    } else {
      _streamTransferHave(stream, msg.sender, amountOut);
    }

    stream.want.transferFrom(msg.sender, stream.target, amountIn);

    return amountOut;
  }

  function getLiquidationState(uint256 streamId) external view returns (
    int exchangeRate,
    uint256 lastSaleTime
  ) {
    LiquidatorLib.State memory state = liquidatorStates[streamId];
    exchangeRate = state.exchangeRate.value;
    lastSaleTime = state.lastSaleTime;
  }
}
