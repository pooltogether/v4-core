// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../prize-strategy/PrizeSplit.sol";

contract PrizeSplitHarness is PrizeSplit {

  constructor(address _owner) Ownable(_owner) {}

  function _awardPrizeSplitAmount(address target, uint256 amount) internal override {}
}
