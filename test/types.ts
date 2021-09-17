import { BigNumber } from "ethers"

export type TsunamiDrawCalculatorSettings = {
    matchCardinality: BigNumber;
    numberOfPicks: BigNumber;
    distributions: BigNumber[];
    bitRangeSize: BigNumber;
    prize: BigNumber;
    drawStartTimestampOffset: BigNumber;
    drawEndTimestampOffset: BigNumber;
};

export type Draw = { drawId: BigNumber, winningRandomNumber: BigNumber, timestamp: BigNumber }