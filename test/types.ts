import {BigNumber} from "ethers"

export type DrawSettings = {
    matchCardinality: BigNumber;
    pickCost: BigNumber;
    distributions: BigNumber[];
    bitRangeSize: BigNumber;
};