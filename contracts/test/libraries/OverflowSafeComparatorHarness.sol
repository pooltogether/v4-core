// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../../libraries/OverflowSafeComparator.sol";

contract OverflowSafeComparatorHarness {
  using OverflowSafeComparator for uint32;

  function ltHarness(
    uint32 _a,
    uint32 _b,
    uint32 _timestamp
  ) external pure returns (bool) {
    return _a.lt(_b, _timestamp);
  }

  function lteHarness(
    uint32 _a,
    uint32 _b,
    uint32 _timestamp
  ) external pure returns (bool) {
    return _a.lte(_b, _timestamp);
  }
}
