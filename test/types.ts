import { BigNumber } from "ethers"

export type DrawSettings = {
    matchCardinality: BigNumber;
    pickCost: BigNumber;
    distributions: BigNumber[];
    bitRangeSize: BigNumber;
    prize: BigNumber;
};

export type Draw = { drawId: BigNumber, winningRandomNumber: BigNumber, timestamp: BigNumber }