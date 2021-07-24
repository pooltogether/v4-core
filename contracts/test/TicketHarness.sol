// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../Ticket.sol";

contract TicketHarness is Ticket {
  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}
