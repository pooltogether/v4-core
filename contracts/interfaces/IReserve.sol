// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IReserve {
  function withdrawTo(address recipient, uint256 amount) external;
  function checkpoint() external;
  function getToken() external view returns (IERC20);
  function getReserveAccumulatedBetween(uint32 startTimestamp, uint32 endTimestamp) external returns (uint224);

  event Checkpoint(uint256 reserveAccumulated, uint256 withdrawAccumulated);
  event Withdrawn(address indexed recipient, uint256 amount);
}
