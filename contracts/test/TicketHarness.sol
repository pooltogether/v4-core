// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import '../Ticket.sol';

contract TicketHarness is Ticket {
  function getBalances(address user) external view returns (Balance[CARDINALITY] memory) {
    return balances[user];
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}
