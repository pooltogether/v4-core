// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

interface IStrategy {
  /**
    * @notice Capture the award balance and distribute to prize splits.
    * @dev    Permissionless function to initialize distribution of interst
    * @return Prize captured from PrizePool
  */
  function distribute() external returns (uint256);
}
