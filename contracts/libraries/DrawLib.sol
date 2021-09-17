// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

library DrawLib{

    struct Draw {
        uint256 winningRandomNumber;
        uint32 timestamp;
        uint32 drawId;
    }

    ///@notice Draw settings struct
    ///@param bitRangeSize Decimal representation of bitRangeSize
    ///@param matchCardinality The bitRangeSize's to consider in the 256 random numbers. Must be > 1 and < 256/bitRangeSize
    ///@param numberOfPicks Number of picks this Draw has (may vary network to network)
    ///@param distributions Array of prize distribution percentages, expressed in fraction form with base 1e18. Max sum of these <= 1 Ether. ordering: index0: grandPrize, index1: runnerUp, etc.
    ///@param prize Total prize amount available in this draw calculator for this Draw (may vary from network to network)
    struct DrawSettings {
        uint8 bitRangeSize;
        uint16 matchCardinality;
        uint32 drawStartTimestampOffset;
        uint32 drawEndTimestampOffset;
        uint64 numberOfPicks;
        uint128[] distributions;
        uint256 prize;
    }
}