pragma solidity 0.8.6;

import "../DrawHistory.sol";
import "../test/PeriodicPrizeStrategyDistributorInterface.sol";

/* solium-disable security/no-block-members */
contract DrawHistoryHarness is DrawHistory {

  /**
    * @notice External function to create a new draw.
    * @dev External function to create a new draw from an authorized draw manager.
    * @param randomNumber  Randomly generated draw number
    * @param timestamp     Epoch timestamp of the draw
    * @return New draw id
  */
  function createDraw(uint32 timestamp, uint256 randomNumber) external onlyDrawManagerOrOwner returns (uint256) {
    return _createDraw(timestamp, randomNumber);
  }

}