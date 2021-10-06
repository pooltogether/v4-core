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
    event DrawSet(uint32 indexed drawId, uint32 timestamp, uint256 winningRandomNumber);

    /**
     * @notice Emitted when the PrizeDistribution are set/updated
     * @param drawId       Draw id
     * @param prizeDistributions DrawLib.PrizeDistribution
     */
    event PrizeDistributionsSet(
        uint32 indexed drawId,
        DrawLib.PrizeDistribution prizeDistributions
    );

    /**
     * @notice Read the newest PrizeDistribution from the prize distributions ring buffer.
     * @dev    Uses the nextDrawIndex to calculate the most recently added PrizeDistribution.
     * @return prizeDistribution stored in ring buffer
     * @return drawId stored in ring buffer
     */
    function getNewestPrizeDistribution()
        external
        view
        returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId);

    /**
     * @notice Read the oldest PrizeDistribution from the prize distributions ring buffer.
     * @dev    Finds the oldest Draw by buffer.nextIndex and buffer.lastDrawId
     * @return prizeDistribution stored in ring buffer
     * @return drawId stored in ring buffer
     */
    function getOldestPrizeDistribution()
        external
        view
        returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId);

    /**
     * @notice Gets array of PrizeDistributions for drawIds
     * @param drawIds drawIds to get PrizeDistribution for
     */
    function getPrizeDistributions(uint32[] calldata drawIds)
        external
        view
        returns (DrawLib.PrizeDistribution[] memory);

    /**
     * @notice Gets the PrizeDistributionHistory for a drawId
     * @param drawId Draw.drawId
     */
    function getPrizeDistribution(uint32 drawId)
        external
        view
        returns (DrawLib.PrizeDistribution memory);

    /**
     * @notice Gets the number of PrizeDistributions stored in the prize distributions ring buffer.
     * @dev If no Draws have been pushed, it will return 0.
     * @dev If the ring buffer is full, it will return the cardinality.
     * @dev Otherwise, it will return the NewestPrizeDistribution index + 1.
     * @return Number of PrizeDistributions stored in the prize distributions ring buffer.
     */
    function getPrizeDistributionCount() external view returns (uint32);

    /**
     * @notice Stores a PrizeDistribution for a drawId
     * @dev    Only callable by the owner or manager
     * @param drawId drawId to store PrizeDistribution for
     * @param prizeDistribution   PrizeDistribution to store
     */
    function pushPrizeDistribution(
        uint32 drawId,
        DrawLib.PrizeDistribution calldata prizeDistribution
    ) external returns (bool);

    /**
     * @notice Set existing Draw in prize distributions ring buffer with new parameters.
     * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.
     * @return Draw.drawId
     */
    function setPrizeDistribution(uint32 drawId, DrawLib.PrizeDistribution calldata draw)
        external
        returns (uint32); // maybe return drawIndex
}
