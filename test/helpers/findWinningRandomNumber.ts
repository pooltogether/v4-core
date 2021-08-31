import { deployMockContract } from 'ethereum-waffle';
import { utils, Contract, BigNumber, Wallet } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { DrawSettings } from '../types';
import { deployDrawCalculator } from '../TsunamiDrawCalculator.test';

const printUtils = require("./printUtils")
const { green, dim } = printUtils


const encoder = ethers.utils.defaultAbiCoder

async function findWinningNumberForUser(wallet1: any, userAddress: string, matchesRequired: number, drawSettings: DrawSettings) {
    dim(`searching for ${matchesRequired} winning numbers for ${userAddress} with drawSettings ${JSON.stringify(drawSettings)}..`)
    const drawCalculator: Contract = await deployDrawCalculator(wallet1)
    
    let ticketArtifact = await artifacts.readArtifact('Ticket')
    let ticket = await deployMockContract(wallet1, ticketArtifact.abi)
    
    await drawCalculator.initialize(ticket.address, drawSettings)
    
    const timestamp = 42
    const prizes = [utils.parseEther("1")]
    const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
    const ticketBalance = utils.parseEther("10")

    await ticket.mock.getBalancesAt.withArgs(userAddress, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance

    const distributionIndex = drawSettings.matchCardinality.toNumber() - matchesRequired
    dim(`distributionIndex: ${distributionIndex}`)

    if(drawSettings.distributions.length < distributionIndex){
       throw new Error(`There are only ${drawSettings.distributions.length} tiers of prizes`) // there is no "winning number" in this case
    }

    // now calculate the expected prize amount for these settings
    const fraction : BigNumber =  await drawCalculator.calculatePrizeDistributionFraction(drawSettings, distributionIndex)
    
    const expectedPrizeAmount : BigNumber = (prizes[0]).mul(fraction as any).div(ethers.constants.WeiPerEther) 

    dim(`expectedPrizeAmount: ${utils.formatEther(expectedPrizeAmount as any)}`)
    let winningRandomNumber

    while(true){
        winningRandomNumber = utils.solidityKeccak256(["address"], [ethers.Wallet.createRandom().address])
        const prizesAwardable : BigNumber[] = await drawCalculator.calculate(
            userAddress,
            [winningRandomNumber],
            [timestamp],
            prizes,
            pickIndices
        )
        const testEqualTo = (prize: BigNumber): boolean => prize.eq(expectedPrizeAmount)
        if(prizesAwardable.some(testEqualTo)){
          green(`found a winning number! ${winningRandomNumber}`)
          break
        }
    }

    return winningRandomNumber
}