// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "./IReserve.sol";
import "./IStrategy.sol";

interface IPrizeFlush {
  event Flushed(address indexed recipient, uint256 amount);
  function flush(IStrategy strategy, IReserve reserve, address recipient, uint256 amount) external returns (bool);
}
