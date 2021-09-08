// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "../prize-strategy/PrizeSplit.sol";

contract PrizeSplitHarness is PrizeSplit {

  constructor() public {
    __Ownable_init();
  }

  function _awardPrizeSplitAmount(address target, uint256 amount, uint8 tokenIndex) internal override {}
}