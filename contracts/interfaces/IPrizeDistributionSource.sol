// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

/** @title IPrizeDistributionSource
 * @author PoolTogether Inc Team
 * @notice The PrizeDistributionSource interface.
 */
interface IPrizeDistributionSource {
    ///@notice PrizeDistribution struct created every draw
    ///@param bitRangeSize Decimal representation of bitRangeSize
    ///@param matchCardinality The number of numbers to consider in the 256 bit random number. Must be > 1 and < 256/bitRangeSize.
    ///@param startTimestampOffset The starting time offset in seconds from which Ticket balances are calculated.
    ///@param endTimestampOffset The end time offset in seconds from which Ticket balances are calculated.
    ///@param maxPicksPerUser Maximum number of picks a user can make in this draw
    ///@param expiryDuration Length of time in seconds the PrizeDistribution is valid for. Relative to the Draw.timestamp.
    ///@param numberOfPicks Number of picks this draw has (may vary across networks according to how much the network has contributed to the Reserve)
    ///@param tiers Array of prize tiers percentages, expressed in fraction form with base 1e9. Ordering: index0: grandPrize, index1: runnerUp, etc.
    ///@param prize Total prize amount available in this draw calculator for this draw (may vary from across networks)
    struct PrizeDistribution {
        uint8 bitRangeSize;
        uint8 matchCardinality;
        uint32 startTimestampOffset;
        uint32 endTimestampOffset;
        uint32 maxPicksPerUser;
        uint32 expiryDuration;
        uint104 numberOfPicks;
        uint32[16] tiers;
        uint256 prize;
    }

    /**
     * @notice Gets PrizeDistribution list from array of drawIds
     * @param drawIds drawIds to get PrizeDistribution for
     * @return prizeDistributionList
     */
    function getPrizeDistributions(uint32[] calldata drawIds)
        external
        view
        returns (PrizeDistribution[] memory);
}
