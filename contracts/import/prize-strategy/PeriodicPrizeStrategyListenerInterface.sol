// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

/* solium-disable security/no-block-members */
interface PeriodicPrizeStrategyListenerInterface is IERC165Upgradeable {
  function afterPrizePoolAwarded(uint256 randomNumber, uint256 prizePeriodStartedAt) external;
}
