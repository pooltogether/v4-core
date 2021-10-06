// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

interface IPrizeDistributionHistory {

    ///@notice PrizeDistribution struct created every draw
    ///@param bitRangeSize Decimal representation of bitRangeSize
    ///@param matchCardinality The number of numbers to consider in the 256 bit random number. Must be > 1 and < 256/bitRangeSize.
    ///@param startTimestampOffset The starting time offset in seconds from which Ticket balances are calculated.
    ///@param endTimestampOffset The end time offset in seconds from which Ticket balances are calculated.
    ///@param maxPicksPerUser Maximum number of picks a user can make in this draw
    ///@param numberOfPicks Number of picks this draw has (may vary across networks according to how much the network has contributed to the Reserve)
    ///@param tiers Array of prize tiers percentages, expressed in fraction form with base 1e9. Ordering: index0: grandPrize, index1: runnerUp, etc.
    ///@param prize Total prize amount available in this draw calculator for this draw (may vary from across networks)
    struct PrizeDistribution {
        uint8 bitRangeSize;
        uint8 matchCardinality;
        uint32 startTimestampOffset;
        uint32 endTimestampOffset;
        uint32 maxPicksPerUser;
        uint136 numberOfPicks;
        uint32[16] tiers;
        uint256 prize;
    }

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
     * @param prizeDistribution IPrizeDistributionHistory.PrizeDistribution
     */
    event PrizeDistributionSet(
        uint32 indexed drawId,
        IPrizeDistributionHistory.PrizeDistribution prizeDistribution
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
        returns (IPrizeDistributionHistory.PrizeDistribution memory prizeDistribution, uint32 drawId);

    /**
     * @notice Read the oldest PrizeDistribution from the prize distributions ring buffer.
     * @dev    Finds the oldest Draw by buffer.nextIndex and buffer.lastDrawId
     * @return prizeDistribution stored in ring buffer
     * @return drawId stored in ring buffer
     */
    function getOldestPrizeDistribution()
        external
        view
        returns (IPrizeDistributionHistory.PrizeDistribution memory prizeDistribution, uint32 drawId);

    /**
     * @notice Gets array of PrizeDistributions for drawIds
     * @param drawIds drawIds to get PrizeDistribution for
     */
    function getPrizeDistributions(uint32[] calldata drawIds)
        external
        view
        returns (IPrizeDistributionHistory.PrizeDistribution[] memory);

    /**
     * @notice Gets the PrizeDistributionHistory for a drawId
     * @param drawId Draw.drawId
     */
    function getPrizeDistribution(uint32 drawId)
        external
        view
        returns (IPrizeDistributionHistory.PrizeDistribution memory);

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
        IPrizeDistributionHistory.PrizeDistribution calldata prizeDistribution
    ) external returns (bool);

    /**
     * @notice Set existing Draw in prize distributions ring buffer with new parameters.
     * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.
     * @return Draw.drawId
     */
    function setPrizeDistribution(uint32 drawId, IPrizeDistributionHistory.PrizeDistribution calldata draw)
        external
        returns (uint32); // maybe return drawIndex
}
