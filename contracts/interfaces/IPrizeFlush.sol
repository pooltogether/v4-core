// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "./IReserve.sol";
import "./IStrategy.sol";

interface IPrizeFlush {
  // Events
  event Flushed(address indexed recipient, uint256 amount);
  event DestinationSet(address destination);
  event StrategySet(IStrategy strategy);
  event ReserveSet(IReserve reserve);

  /// @notice Read global destination variable.
  function getDestination() external view returns (address);
  
  /// @notice Read global reserve variable.
  function getReserve() external view returns (IReserve);
  
  /// @notice Read global strategy variable.
  function getStrategy() external view returns (IStrategy);

  /// @notice Set global destination variable.
  function setDestination(address _destination) external returns (address);
  
  /// @notice Set global reserve variable.
  function setReserve(IReserve _reserve) external returns (IReserve);
  
  /// @notice Set global strategy variable.
  function setStrategy(IStrategy _strategy) external returns (IStrategy);
  
  /**
    * @notice Migrate interest from PrizePool to DrawPrizes in single transaction.
    * @dev    Captures interest, checkpoint data and transfers tokens to final destination.
   */
  function flush() external returns (bool);
}
