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
    ///@param pickCost Amount of ticket balance required per pick
    ///@param distributions Array of prize distribution percentages, expressed in fraction form with base 1e18. Max sum of these <= 1 Ether. ordering: index0: grandPrize, index1: runnerUp, etc.
    struct DrawSettings {
        uint8 bitRangeSize;
        uint16 matchCardinality;
        uint224 pickCost;
        uint128[] distributions;
        uint256 prize;
    }

}