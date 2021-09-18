import { BigNumber } from "ethers"

export type DrawSettings = {
    matchCardinality: BigNumber;
    numberOfPicks: BigNumber;
    distributions: BigNumber[];
    bitRangeSize: BigNumber;
    prize: BigNumber;
    drawStartTimestampOffset: BigNumber;
    drawEndTimestampOffset: BigNumber;
    maxPicksPerUser: BigNumber;
};

export type Draw = { drawId: BigNumber, winningRandomNumber: BigNumber, timestamp: BigNumber }