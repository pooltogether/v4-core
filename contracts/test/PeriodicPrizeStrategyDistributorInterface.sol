pragma solidity 0.8.6;

import "../prize-strategy/PeriodicPrizeStrategy.sol";

/* solium-disable security/no-block-members */
interface PeriodicPrizeStrategyDistributorInterface {
  function distribute(uint256 randomNumber) external returns (uint256);
}