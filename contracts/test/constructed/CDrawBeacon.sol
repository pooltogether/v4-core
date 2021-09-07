// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../DrawBeacon.sol";

contract CDrawBeacon is DrawBeacon {
  constructor (
    uint256 _rngRequestPeriodStart,
    uint256 _drawPeriodSeconds,
    RNGInterface _rng
  ) {
    initialize(_rngRequestPeriodStart, _drawPeriodSeconds, _rng);
  }
}
