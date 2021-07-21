// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface ITicket {
  function getBalance(address user, uint256 timestamp) virtual public returns(uint256 balance);
}
