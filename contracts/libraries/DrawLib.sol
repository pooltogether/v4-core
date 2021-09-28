// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

library DrawLib {

    struct Draw {
        uint256 winningRandomNumber;
        uint32 drawId;
        uint64 timestamp;
        uint64 beaconPeriodStartedAt;
        uint32 beaconPeriodSeconds;
    }

    uint8 public constant DISTRIBUTIONS_LENGTH = 16;

    ///@notice Draw settings for the tsunami draw calculator
    ///@param bitRangeSize Decimal representation of bitRangeSize
    ///@param matchCardinality The bitRangeSize's to consider in the 256 random numbers. Must be > 1 and < 256/bitRangeSize
    ///@param startTimestampOffset The starting time offset in seconds from which Ticket balances are calculated.
    ///@param endTimestampOffset The end time offset in seconds from which Ticket balances are calculated.
    ///@param maxPicksPerUser Maximum number of picks a user can make in this Draw
    ///@param numberOfPicks Number of picks this Draw has (may vary network to network)
    ///@param distributions Array of prize distributions percentages, expressed in fraction form with base 1e18. Max sum of these <= 1 Ether. ordering: index0: grandPrize, index1: runnerUp, etc.
    ///@param prize Total prize amount available in this draw calculator for this Draw (may vary from network to network)
    struct PrizeDistribution {
        uint8 bitRangeSize;
        uint8 matchCardinality;
        uint32 startTimestampOffset;
        uint32 endTimestampOffset;
        uint32 maxPicksPerUser;
        uint136 numberOfPicks;
        uint32[DISTRIBUTIONS_LENGTH] distributions;
        uint256 prize;
    }

}
