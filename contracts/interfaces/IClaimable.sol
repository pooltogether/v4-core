// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

interface IClaimable {
  function claim(address user, uint256[] calldata timestamps, uint256[] calldata balances, bytes calldata data) external returns (uint256);
}
