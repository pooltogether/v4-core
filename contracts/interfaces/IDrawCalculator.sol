// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

interface IDrawCalculator {
  function calculate(address user, uint256[] calldata randomNumbers, uint32[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external returns (uint256[] memory);
  
}