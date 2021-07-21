// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface ITicket {
  function getBalance(address user, uint256 timestamp) virtual public returns(uint256 balance);
}
