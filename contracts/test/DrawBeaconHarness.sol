pragma solidity 0.8.6;

import "../DrawBeacon.sol";
import "../test/PeriodicPrizeStrategyDistributorInterface.sol";

/* solium-disable security/no-block-members */
contract DrawBeaconHarness is DrawBeacon {

  function saveRNGRequestWithDraw(uint256 randomNumber) external returns (uint256) {
    return _saveRNGRequestWithDraw(randomNumber);
  }

}