// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

/// @notice The interface for the Periodic Prize Strategy before award listener.  This listener will be called immediately before the award is distributed.
interface BeforeAwardListenerInterface is IERC165Upgradeable {
  /// @notice Called immediately before the award is distributed
  function beforePrizePoolAwarded(uint256 randomNumber, uint256 prizePeriodStartedAt, uint256 prize) external;
}
