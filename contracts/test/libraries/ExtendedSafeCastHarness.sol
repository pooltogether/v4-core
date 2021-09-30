// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../../libraries/ExtendedSafeCast.sol";

contract ExtendedSafeCastHarness {
  using ExtendedSafeCast for uint256;

  function toUint208(
    uint256 value
  ) external pure returns (uint208) {
    return value.toUint208();
  }
}
