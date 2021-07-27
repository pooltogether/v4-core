// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "./IClaimable.sol";

interface IClaimer {
  function claim(address user, IClaimable claimable, uint256[] calldata timestamps, bytes calldata data) external returns (uint256);
}
