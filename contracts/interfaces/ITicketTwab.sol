// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface ITicketTwab {
  function getBalance(address user, uint32 timestamp) external view returns(uint256);
  function getBalances(address user, uint32[] calldata timestamp) external view returns(uint256[] memory);
  function getTotalSupply(uint32 timestamp) external view returns(uint256);
  function getTotalSupplies(uint32[] calldata timestamp) external view returns(uint256[] memory);
}
