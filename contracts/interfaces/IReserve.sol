// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IReserve {
  event Checkpoint(uint256 reserveAccumulated, uint256 withdrawAccumulated);
  event Withdrawn(address indexed recipient, uint256 amount);

  /**
    * @notice Create observation checkpoint in ring bufferr.
    * @dev    Calculates total desposited tokens since last checkpoint and creates new accumulator checkpoint.
  */
  function checkpoint() external;
  
  /**
    * @notice Read global token value.
    * @return IERC20
  */
  function getToken() external view returns (IERC20);

  /**
    * @notice Calculate token accumulation beween timestamp range.
    * @dev    Search the ring buffer for two checkpoint observations and diffs accumulator amount. 
    * @param startTimestamp Account address 
    * @param endTimestamp   Transfer amount
    */
  function getReserveAccumulatedBetween(uint32 startTimestamp, uint32 endTimestamp) external returns (uint224);

  /**
    * @notice Transfer Reserve token balance to recipient address.
    * @dev    Creates checkpoint before token transfer. Increments withdrawAccumulator with amount.
    * @param recipient Account address 
    * @param amount    Transfer amount
  */
  function withdrawTo(address recipient, uint256 amount) external;
}
