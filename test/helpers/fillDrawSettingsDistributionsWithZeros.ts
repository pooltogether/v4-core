import { BigNumber } from "ethers"

export function fillDrawSettingsDistributionsWithZeros(distributions: BigNumber[]): BigNumber[]{
    const existingLength = distributions.length
    const lengthOfZeroesRequired = 16 - existingLength
    return [...distributions, ...Array(lengthOfZeroesRequired).fill(BigNumber.from(0))]
}

module.exports = { fillDrawSettingsDistributionsWithZeros }