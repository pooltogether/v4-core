// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./IReserve.sol";
import "./IStrategy.sol";

interface IPrizeFlush {
    /* ============ Events ============ */

    event Flushed(address indexed recipient, uint256 amount);

    event DestinationSet(address indexed destination);

    event StrategySet(IStrategy indexed strategy);

    event ReserveSet(IReserve indexed reserve);

    /* ============ External Functions ============ */

    /**
     * @notice Read global destination variable.
     * @return Destination address.
     */
    function getDestination() external view returns (address);

    /**
     * @notice Read global reserve variable.
     * @return Reserve address.
     */
    function getReserve() external view returns (IReserve);

    /**
     * @notice Read global strategy variable.
     * @return Strategy address.
     */
    function getStrategy() external view returns (IStrategy);

    /**
     * @notice Set global destination variable.
     * @dev Only the owner can set the destination.
     * @param _destination Destination address.
     * @return Destination address.
     */
    function setDestination(address _destination) external returns (address);

    /**
     * @notice Set global reserve variable.
     * @dev Only the owner can set the reserve.
     * @param _reserve Reserve address.
     * @return Reserve address.
     */
    function setReserve(IReserve _reserve) external returns (IReserve);

    /**
     * @notice Set global strategy variable.
     * @dev Only the owner can set the strategy.
     * @param _strategy Strategy address.
     * @return Strategy address.
     */
    function setStrategy(IStrategy _strategy) external returns (IStrategy);

    /**
     * @notice Migrate interest from PrizePool to DrawPrize in a single transaction.
     * @dev Captures interest, checkpoint data and transfers tokens to final destination.
     * @dev Only callable by the owner or manager.
     * @return True when operation is successful.
     */
    function flush() external returns (bool);
}
