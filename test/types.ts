import { BigNumber } from 'ethers'

export type PrizeDistribution = {
    matchCardinality: BigNumber;
    numberOfPicks: BigNumber;
    tiers: BigNumber[];
    bitRangeSize: BigNumber;
    prize: BigNumber;
    startTimestampOffset: BigNumber;
    endTimestampOffset: BigNumber;
    maxPicksPerUser: BigNumber;
    expiryDuration: BigNumber;
};

export type PrizeConfig = {
     bitRangeSize: BigNumber;
    matchCardinality: BigNumber;
    maxPicksPerUser: BigNumber;
    drawId: BigNumber;
    expiryDuration: BigNumber;
    endTimestampOffset: BigNumber;
    poolStakeCeiling: BigNumber;
    prize: BigNumber;
    tiers: BigNumber[];
};

export type Draw = { drawId: BigNumber, winningRandomNumber: BigNumber, timestamp: BigNumber }
