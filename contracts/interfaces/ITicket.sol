// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ITicket {
  function getBalance(address user, uint32 timestamp) external view returns(uint256);
}
