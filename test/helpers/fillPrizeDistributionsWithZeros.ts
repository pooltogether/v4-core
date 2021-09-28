import { BigNumber } from 'ethers';

export function fillPrizeDistributionsWithZeros(distributions: BigNumber[]): BigNumber[]{
    const existingLength = distributions.length
    const lengthOfZeroesRequired = 16 - existingLength
    return [...distributions, ...Array(lengthOfZeroesRequired).fill(BigNumber.from(0))]
}
