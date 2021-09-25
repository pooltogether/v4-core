import { BigNumber } from "ethers"

export type DrawCalculatorSettings = {
    matchCardinality: BigNumber;
    numberOfPicks: BigNumber;
    distributions: BigNumber[];
    bitRangeSize: BigNumber;
    prize: BigNumber;
    startOffsetTimestamp: BigNumber;
    endOffsetTimestamp: BigNumber;
    maxPicksPerUser: BigNumber;
};

export type Draw = { drawId: BigNumber, winningRandomNumber: BigNumber, timestamp: BigNumber }