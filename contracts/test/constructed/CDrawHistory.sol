// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../DrawHistory.sol";

contract CDrawHistory is DrawHistory {
  constructor (
    address _manager
  ) {
    initialize(_manager);
  }
}
