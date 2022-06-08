// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../PrizePoolLiquidator.sol";

contract PrizePoolLiquidatorHarness is PrizePoolLiquidator {

  constructor(address _owner) PrizePoolLiquidator(_owner) {}

}
