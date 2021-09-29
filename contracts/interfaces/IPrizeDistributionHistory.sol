// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "../libraries/DrawLib.sol";

interface IPrizeDistributionHistory {

  /**
    * @notice Emit when a new draw has been created.
    * @param drawId       Draw id
    * @param timestamp    Epoch timestamp when the draw is created.
    * @param winningRandomNumber Randomly generated number used to calculate draw winning numbers
  */
  event DrawSet (
    uint32 indexed drawId,
    uint32 timestamp,
    uint256 winningRandomNumber
  );

  /**
    * @notice Emitted when the DrawParams are set/updated
    * @param drawId       Draw id
    * @param prizeDistributions DrawLib.PrizeDistribution
  */
  event PrizeDistributionsSet(uint32 indexed drawId, DrawLib.PrizeDistribution prizeDistributions);


  /**
    * @notice Read newest PrizeDistributions from the prize distributions ring buffer.
    * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
    * @return prizeDistribution DrawLib.PrizeDistribution
    * @return drawId Draw.drawId
  */
  function getNewestPrizeDistribution() external view returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId);

  /**
    * @notice Read oldest PrizeDistributions from the prize distributions ring buffer.
    * @dev    Finds the oldest Draw by buffer.nextIndex and buffer.lastDrawId
    * @return prizeDistribution DrawLib.PrizeDistribution
    * @return drawId Draw.drawId
  */
  function getOldestPrizeDistribution() external view returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId);

  /**
    * @notice Gets array of PrizeDistributionHistory for Draw.drawID(s)
    * @param drawIds Draw.drawId
   */
  function getPrizeDistributions(uint32[] calldata drawIds) external view returns (DrawLib.PrizeDistribution[] memory);

  /**
    * @notice Gets the PrizeDistributionHistory for a Draw.drawID
    * @param drawId Draw.drawId
   */
  function getPrizeDistribution(uint32 drawId) external view returns (DrawLib.PrizeDistribution memory);

  /**
    * @notice Sets PrizeDistributionHistory for a Draw.drawID.
    * @dev    Only callable by the owner or manager
    * @param drawId Draw.drawId
    * @param draw   PrizeDistributionHistory struct
   */
  function pushPrizeDistribution(uint32 drawId, DrawLib.PrizeDistribution calldata draw) external returns(bool);

  /**
    * @notice Set existing Draw in prize distributions ring buffer with new parameters.
    * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.
    * @return Draw.drawId
  */
  function setPrizeDistribution(uint32 drawId, DrawLib.PrizeDistribution calldata draw) external returns(uint32); // maybe return drawIndex

}
