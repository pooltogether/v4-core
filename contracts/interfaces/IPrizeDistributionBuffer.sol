// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./IPrizeDistributionSource.sol";

/** @title  IPrizeDistributionBuffer
 * @author PoolTogether Inc Team
 * @notice The PrizeDistributionBuffer interface.
 */
interface IPrizeDistributionBuffer is IPrizeDistributionSource {
    /**
     * @notice Emit when PrizeDistribution is set.
     * @param drawId       Draw id
     * @param prizeDistribution IPrizeDistributionBuffer.PrizeDistribution
     */
    event PrizeDistributionSet(
        uint32 indexed drawId,
        IPrizeDistributionBuffer.PrizeDistribution prizeDistribution
    );

    /**
     * @notice Read a ring buffer cardinality
     * @return Ring buffer cardinality
     */
    function getBufferCardinality() external view returns (uint32);

    /**
     * @notice Read newest PrizeDistribution from prize distributions ring buffer.
     * @dev    Uses nextDrawIndex to calculate the most recently added PrizeDistribution.
     * @return prizeDistribution
     * @return drawId
     */
    function getNewestPrizeDistribution()
        external
        view
        returns (
            IPrizeDistributionBuffer.PrizeDistribution memory prizeDistribution,
            uint32 drawId
        );

    /**
     * @notice Read oldest PrizeDistribution from prize distributions ring buffer.
     * @dev    Finds the oldest Draw by buffer.nextIndex and buffer.lastDrawId
     * @return prizeDistribution
     * @return drawId
     */
    function getOldestPrizeDistribution()
        external
        view
        returns (
            IPrizeDistributionBuffer.PrizeDistribution memory prizeDistribution,
            uint32 drawId
        );

    /**
     * @notice Gets the PrizeDistributionBuffer for a drawId
     * @param drawId drawId
     * @return prizeDistribution
     */
    function getPrizeDistribution(uint32 drawId)
        external
        view
        returns (IPrizeDistributionBuffer.PrizeDistribution memory);

    /**
     * @notice Gets the number of PrizeDistributions stored in the prize distributions ring buffer.
     * @dev If no Draws have been pushed, it will return 0.
     * @dev If the ring buffer is full, it will return the cardinality.
     * @dev Otherwise, it will return the NewestPrizeDistribution index + 1.
     * @return Number of PrizeDistributions stored in the prize distributions ring buffer.
     */
    function getPrizeDistributionCount() external view returns (uint32);

    /**
     * @notice Adds new PrizeDistribution record to ring buffer storage.
     * @dev    Only callable by the owner or manager
     * @param drawId            Draw ID linked to PrizeDistribution parameters
     * @param prizeDistribution PrizeDistribution parameters struct
     */
    function pushPrizeDistribution(
        uint32 drawId,
        IPrizeDistributionBuffer.PrizeDistribution calldata prizeDistribution
    ) external returns (bool);

    /**
     * @notice Sets existing PrizeDistribution with new PrizeDistribution parameters in ring buffer storage.
     * @dev    Retroactively updates an existing PrizeDistribution and should be thought of as a "safety"
               fallback. If the manager is setting invalid PrizeDistribution parameters the Owner can update
               the invalid parameters with correct parameters.
     * @return drawId
     */
    function setPrizeDistribution(
        uint32 drawId,
        IPrizeDistributionBuffer.PrizeDistribution calldata draw
    ) external returns (uint32);
}
