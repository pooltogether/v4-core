// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface TicketInterface {
  function getBalanceAt(address user, uint32 timestamp) external view returns(uint256);
  function getBalancesAt(address user, uint32[] calldata timestamp) external view returns(uint256[] memory);
  function getAverageBalanceBetween(address _user, uint32 _startTime, uint32 _endTime) external view returns (uint256);
  function getTotalSupply(uint32 timestamp) external view returns(uint256);
  function getTotalSupplies(uint32[] calldata timestamp) external view returns(uint256[] memory);
}
