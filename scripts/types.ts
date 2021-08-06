import { BigNumber } from "ethers";

export type DrawSettings  = {
    matchCardinality: BigNumber
    pickCost: BigNumber
    distributions: BigNumber[]
    bitRangeValue: BigNumber
    bitRangeSize: BigNumber
}

export type Draw = {
    timestamp : number // dont think this is needed in the sim since single Draw simulated
    prize: BigNumber
    winningRandomNumber: BigNumber
}

export type User = {
    address: string
    balance: BigNumber
    pickIndices: BigNumber[]
}

export type DrawSimulationResult = {
    draw: Draw // think all we need from this is the winningRandomNumber
    user: User // need address - do we need pickIndices?
    drawSettings: DrawSettings
    prizeReceived : BigNumber
}

export type DrawSimulationResults = {
    results: DrawSimulationResult[][]
}