import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { deployMockContract } from 'ethereum-waffle';
import { utils, Contract, BigNumber, Wallet } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Draw, TsunamiDrawCalculatorSettings } from '../types';

const { getSigners } = ethers;
const printUtils = require("./printUtils")
const { green, dim } = printUtils
const encoder = ethers.utils.defaultAbiCoder

async function deployDrawCalculator(signer: any): Promise<Contract> {
  const drawCalculatorFactory = await ethers.getContractFactory(
    'TsunamiDrawCalculatorHarness',
    signer,
  );
  const drawCalculator: Contract = await drawCalculatorFactory.deploy();

  return drawCalculator;
}



async function findWinningNumberForUser(wallet1: any, userAddress: string, matchesRequired: number, drawSettings: TsunamiDrawCalculatorSettings) {
  dim(`searching for ${matchesRequired} winning numbers for ${userAddress} with drawSettings ${JSON.stringify(drawSettings)}..`)
  const drawCalculator: Contract = await deployDrawCalculator(wallet1)
  let ticketArtifact = await artifacts.readArtifact('Ticket')
  let ticket = await deployMockContract(wallet1, ticketArtifact.abi)

  await drawCalculator.initialize(ticket.address, wallet1.address, 0, drawSettings)

  const timestamp = 42
  const prizes = [utils.parseEther("1")]
  const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
  const ticketBalance = utils.parseEther("10")

  await ticket.mock.getBalancesAt.withArgs(userAddress, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance

  const distributionIndex = drawSettings.matchCardinality.toNumber() - matchesRequired
  dim(`distributionIndex: ${distributionIndex}`)


  if (drawSettings.distributions.length < distributionIndex) {
    throw new Error(`There are only ${drawSettings.distributions.length} tiers of prizes`) // there is no "winning number" in this case
  }

  // now calculate the expected prize amount for these settings
  const fraction: BigNumber = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, distributionIndex)

  const expectedPrizeAmount: BigNumber = (prizes[0]).mul(fraction as any).div(ethers.constants.WeiPerEther)

  dim(`expectedPrizeAmount: ${utils.formatEther(expectedPrizeAmount as any)}`)
  let winningRandomNumber

  while (true) {
    winningRandomNumber = utils.solidityKeccak256(["address"], [ethers.Wallet.createRandom().address])

    const draw: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp) }

    const prizesAwardable: BigNumber[] = await drawCalculator.calculate(
      userAddress,
      [draw],
      prizes,
      pickIndices
    )
    const testEqualTo = (prize: BigNumber): boolean => prize.eq(expectedPrizeAmount)
    if (prizesAwardable.some(testEqualTo)) {
      green(`found a winning number! ${winningRandomNumber}`)
      break
    }
  }

  return winningRandomNumber
}

async function runFindWinningRandomNumbers() {
  let wallet1: SignerWithAddress
  [wallet1] = await getSigners();

  let drawSettings: TsunamiDrawCalculatorSettings = {
    matchCardinality: BigNumber.from(7),
    distributions: [
      ethers.utils.parseUnits("0.2", 9),
      ethers.utils.parseUnits("0.1", 9),
      ethers.utils.parseUnits("0.1", 9),
      ethers.utils.parseUnits("0.1", 9),
    ],
    numberOfPicks: BigNumber.from(utils.parseEther('1')),
    bitRangeSize: BigNumber.from(4),
    prize: ethers.utils.parseEther('100'),
    drawStartTimestampOffset: BigNumber.from(1),
    drawEndTimestampOffset: BigNumber.from(1),
    maxPicksPerUser: BigNumber.from(1001),
  };

  const result = await findWinningNumberForUser(wallet1, wallet1.address, 3, drawSettings)
  console.log(result)
}