import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Draw, DrawCalculatorSettings } from './types';
import { fillDrawSettingsDistributionsWithZeros } from './helpers/fillDrawSettingsDistributionsWithZeros';

const { getSigners } = ethers;

const newDebug = require('debug')

function newDraw(overrides: any): Draw {
  return {
    drawId: 1,
    timestamp: 0,
    winningRandomNumber: 2,
    beaconPeriodStartedAt: 0,
    beaconPeriodSeconds: 1,
    ...overrides
  }
}

export async function deployDrawCalculator(signer: any, ticketAddress: string, drawHistoryAddress: string, drawSettingsHistoryAddress: string): Promise<Contract> {
  const drawCalculatorFactory = await ethers.getContractFactory(
    'DrawCalculatorHarness',
    signer,
  );
  const drawCalculator: Contract = await drawCalculatorFactory.deploy(signer.address, ticketAddress, drawHistoryAddress, drawSettingsHistoryAddress);

  return drawCalculator;
}

function calculateNumberOfWinnersAtIndex(bitRangeSize: number, distributionIndex: number): BigNumber {
  // Prize Count = (2**bitRange)**(cardinality-numberOfMatches)
  // if not grand prize: - (2^bitRange)**(cardinality-numberOfMatches-1) - ... (2^bitRange)**(0)
  let prizeCount = BigNumber.from(2).pow(bitRangeSize).pow(distributionIndex)
  if (distributionIndex > 0) {
    while (distributionIndex > 0) {
      prizeCount = prizeCount.sub(BigNumber.from((BigNumber.from(2).pow(BigNumber.from(bitRangeSize)).pow(distributionIndex - 1))))
      distributionIndex--
    }
  }
  return prizeCount
}

function modifyTimestampsWithOffset(timestamps: number[], offset: number): number[] {
  return timestamps.map((timestamp: number) => timestamp - offset);
}

describe('DrawCalculator', () => {
  let drawCalculator: Contract;
  let ticket: MockContract;
  let drawHistory: MockContract;
  let drawSettingsHistory: MockContract;
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;

  const encoder = ethers.utils.defaultAbiCoder

  beforeEach(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();

    let ticketArtifact = await artifacts.readArtifact('Ticket');
    ticket = await deployMockContract(wallet1, ticketArtifact.abi);

    let drawHistoryArtifact = await artifacts.readArtifact('DrawHistory');
    drawHistory = await deployMockContract(wallet1, drawHistoryArtifact.abi);

    let drawSettingsHistoryArtifact = await artifacts.readArtifact('PrizeDistributionHistory')
    drawSettingsHistory = await deployMockContract(wallet1, drawSettingsHistoryArtifact.abi)

    drawCalculator = await deployDrawCalculator(wallet1, ticket.address, drawHistory.address, drawSettingsHistory.address);
  });

  describe('constructor()', () => {
    it('should require non-zero ticket', async () => {
      await expect(deployDrawCalculator(wallet1, ethers.constants.AddressZero, drawHistory.address, drawSettingsHistory.address)).to.be.revertedWith('DrawCalc/ticket-not-zero')
    })

    it('should require non-zero settings history', async () => {
      await expect(deployDrawCalculator(wallet1, ticket.address, drawHistory.address, ethers.constants.AddressZero)).to.be.revertedWith('DrawCalc/tdsh-not-zero')
    })

    it('should require a non-zero history', async () => {
      await expect(deployDrawCalculator(wallet1, ticket.address, ethers.constants.AddressZero, drawSettingsHistory.address)).to.be.revertedWith('DrawCalc/dh-not-zero')
    })
  })

  describe('getDrawHistory()', () => {
    it('should succesfully read draw history', async () => {
      expect(await drawCalculator.getDrawHistory())
        .to.equal(drawHistory.address)
    });
  });

  describe('getPrizeDistributionHistory()', () => {
    it('should succesfully read draw history', async () => {
      expect(await drawCalculator.getPrizeDistributionHistory())
        .to.equal(drawSettingsHistory.address)
    });
  });

  describe('calculateDistributionIndex()', () => {
    let drawSettings: DrawCalculatorSettings

    beforeEach(async () => {
      drawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      await drawSettingsHistory.mock.getDrawSettings.returns([drawSettings])
    })

    it('grand prize gets the full fraction at index 0', async () => {
      const amount = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, BigNumber.from(0));
      expect(amount).to.equal(drawSettings.distributions[0]);
    })

    it('runner up gets part of the fraction at index 1', async () => {
      const amount = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, BigNumber.from(1));
      const prizeCount = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), 1)
      const expectedPrizeFraction = drawSettings.distributions[1].div(prizeCount)
      expect(amount).to.equal(expectedPrizeFraction);
    })

    it('all distribution indexes', async () => {
      for (let numberOfMatches = 0; numberOfMatches < drawSettings.distributions.length; numberOfMatches++) {
        
        const distributionIndex = BigNumber.from(drawSettings.distributions.length - numberOfMatches - 1) // minus one because we start at 0
        
        const fraction = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, distributionIndex);
        
        let prizeCount:BigNumber = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), distributionIndex.toNumber())
        
        const expectedPrizeFraction = drawSettings.distributions[distributionIndex.toNumber()].div(prizeCount)
        expect(fraction).to.equal(expectedPrizeFraction);
      }
    })
  })

  describe('numberOfPrizesForIndex()', () => {
    it('calculates the number of prizes at distribution index 0', async () => {
      const bitRangeSize = 2
      const result = await drawCalculator.numberOfPrizesForIndex(bitRangeSize, BigNumber.from(0));
      expect(result).to.equal(1); // grand prize
    })

    it('calculates the number of prizes at distribution index 1', async () => {
      const bitRangeSize = 3
      const result = await drawCalculator.numberOfPrizesForIndex(bitRangeSize, BigNumber.from(1));
      // Number that match exactly four: 8^1 - 8^0 = 7
      expect(result).to.equal(7)
    })

    it('calculates the number of prizes at distribution index 3', async () => {
      const bitRangeSize = 3
      // numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeDistributionIndex)
      // prizeDistributionIndex = matchCardinality - numberOfMatches
      // matchCardinality = 5, numberOfMatches = 2 

      const result = await drawCalculator.numberOfPrizesForIndex(bitRangeSize, BigNumber.from(3));
      // Number that match exactly two: 8^3 - 8^2 - 8^1 - 8^0 = 439
      expect(result).to.equal(439)
    })

    it('calculates the number of prizes at all distribution indices', async () => {
      let drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.5", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      for (let distributionIndex = 0; distributionIndex < drawSettings.distributions.length; distributionIndex++) {
        const result = await drawCalculator.numberOfPrizesForIndex(drawSettings.bitRangeSize, distributionIndex);
        const expectedNumberOfWinners = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), distributionIndex)
        expect(result).to.equal(expectedNumberOfWinners);
      }
    })

  })

  describe('calculatePrizeDistributionFraction()', () => {
    it('calculates distribution index 0', async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      const winningRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70"
      const userRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70" // intentionally same as winning random number
      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(userRandomNumber, winningRandomNumber, bitMasks)
      // all numbers match so grand prize!
      expect(prizeDistributionIndex).to.eq(BigNumber.from(0))
    })

    it('calculates distribution index 1', async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      // 252: 1111 1100
      // 255  1111 1111

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks.length).to.eq(2) // same as length of matchCardinality
      expect(bitMasks[0]).to.eq(BigNumber.from(15))

      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(252, 255, bitMasks)

      // since the first 4 bits do not match the distribution index will be: (matchCardinality - numberOfMatches )= 2-0 = 2
      expect(prizeDistributionIndex).to.eq(drawSettings.matchCardinality)
    })

    it('calculates distribution index 1', async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(3),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      // 527: 0010 0000 1111
      // 271  0001 0000 1111

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks.length).to.eq(3) // same as length of matchCardinality
      expect(bitMasks[0]).to.eq(BigNumber.from(15))

      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(527, 271, bitMasks)

      // since the first 4 bits do not match the distribution index will be: (matchCardinality - numberOfMatches )= 3-2 = 1
      expect(prizeDistributionIndex).to.eq(BigNumber.from(1))
    })

  })

  describe("createBitMasks()", () => {
    it("creates correct 6 bit masks", async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(6),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(63)) // 111111
      expect(bitMasks[1]).to.eq(BigNumber.from(4032)) // 11111100000

    })

    it("creates correct 4 bit masks", async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(15)) // 1111
      expect(bitMasks[1]).to.eq(BigNumber.from(240)) // 11110000

    })
  })

  describe('setDrawHistory()', () => {
    it('should fail to set DrawHistory by unauthorized user', async () => {
      await expect(drawCalculator.connect(wallet3).setDrawHistory(ethers.Wallet.createRandom().address))
        .to.be.revertedWith('Ownable/caller-not-owner')
    });

    it('should fail to set DrawHistory with zero address', async () => {
      await expect(drawCalculator.setDrawHistory(ethers.constants.AddressZero))
        .to.be.revertedWith('DrawCalc/dh-not-zero')
    });

    it('should succeed to set DrawHistory as owner', async () => {
      await expect(drawCalculator.setDrawHistory(wallet2.address))
        .to.emit(drawCalculator, 'DrawHistorySet')
        .withArgs(wallet2.address);
    });
  });

  describe("calculateNumberOfUserPicks()", () => {
    it("calculates the correct number of user picks", async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from("100"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      const normalizedUsersBalance = utils.parseEther("0.05") // has 5% of the total supply
      const userPicks = await drawCalculator.calculateNumberOfUserPicks(drawSettings, normalizedUsersBalance)
      expect(userPicks).to.eq(BigNumber.from(5))
    })
    it("calculates the correct number of user picks", async () => {
      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      const normalizedUsersBalance = utils.parseEther("0.1") // has 10% of the total supply
      const userPicks = await drawCalculator.calculateNumberOfUserPicks(drawSettings, normalizedUsersBalance)
      expect(userPicks).to.eq(BigNumber.from(10000)) // 10% of numberOfPicks
    })
  })

  describe("checkPrizeDistributionIndicesForDrawId()", () => {
    const drawSettings: DrawCalculatorSettings = {
      matchCardinality: BigNumber.from(5),
      distributions: [
        ethers.utils.parseUnits("0.6", 9),
        ethers.utils.parseUnits("0.1", 9),
        ethers.utils.parseUnits("0.1", 9),
        ethers.utils.parseUnits("0.1", 9),
      ],
      numberOfPicks: BigNumber.from("10"),
      bitRangeSize: BigNumber.from(4),
      prize: ethers.utils.parseEther('1'),
      startTimestampOffset: BigNumber.from(1),
      endTimestampOffset: BigNumber.from(1),
      maxPicksPerUser: BigNumber.from(10),
    };
    drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)

    it("calculates the grand prize distribution index", async () => {
      const timestamps = [42]
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
      const winningRandomNumber = utils.solidityKeccak256(
        ['bytes32', 'uint256'],
        [winningNumber, 1],
      );

      const draw: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })

      await drawSettingsHistory.mock.getDrawSettings.withArgs([draw.drawId]).returns([drawSettings])
      await drawHistory.mock.getDraws.withArgs([draw.drawId]).returns([draw])

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("20"), utils.parseEther("30")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("100"), utils.parseEther("600")]);

      const result = await drawCalculator.checkPrizeDistributionIndicesForDrawId(wallet1.address, [1], draw.drawId)
      expect(result[0].won).to.be.true
      expect(result[0].distributionIndex).to.equal(0)
    })

    it("no matches to return won = false", async () => {
      const timestamps = [42]
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())

      const winningNumber = utils.solidityKeccak256(['address'], [wallet2.address]);
      const winningRandomNumber = utils.solidityKeccak256(
        ['bytes32', 'uint256'],
        [winningNumber, 1],
      );

      const draw: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })

      await drawSettingsHistory.mock.getDrawSettings.withArgs([draw.drawId]).returns([drawSettings])
      await drawHistory.mock.getDraws.withArgs([draw.drawId]).returns([draw])

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("20"), utils.parseEther("30")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("100"), utils.parseEther("600")]);

      const result = await drawCalculator.checkPrizeDistributionIndicesForDrawId(wallet1.address, [1], draw.drawId)

      expect(result[0].won).to.be.false
      expect(result[0].distributionIndex).to.equal(drawSettings.matchCardinality.toNumber())
    })

    it("reverts if user has too many picks", async () => {
      const timestamps = [42]
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())

      const winningNumber = utils.solidityKeccak256(['address'], [wallet2.address]);
      const winningRandomNumber = utils.solidityKeccak256(
        ['bytes32', 'uint256'],
        [winningNumber, 1],
      );

      const draw: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })

      await drawSettingsHistory.mock.getDrawSettings.withArgs([draw.drawId]).returns([drawSettings])
      await drawHistory.mock.getDraws.withArgs([draw.drawId]).returns([draw])

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("2")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("10")]);
      // 20pc of the total supply, 10 picks in the draw = 2 picks trying with 3 picks
      await expect(drawCalculator.checkPrizeDistributionIndicesForDrawId(wallet1.address, [1, 2, 3], draw.drawId)).to.be.revertedWith('DrawCalc/insufficient-user-picks');

    })

  })


  describe("getNormalizedBalancesAt()", () => {
    it("calculates the correct normalized balance", async () => {
      const timestamps = [42, 77]

      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

      const draw1: Draw = newDraw({
        drawId: BigNumber.from(1),
        winningRandomNumber: BigNumber.from("1000"),
        timestamp: BigNumber.from(timestamps[0])
      })

      const draw2: Draw = newDraw({
        drawId: BigNumber.from(2),
        winningRandomNumber: BigNumber.from("1000"),
        timestamp: BigNumber.from(timestamps[1])
      })

      await drawHistory.mock.getDraws.returns([draw1, draw2])
      await drawSettingsHistory.mock.getDrawSettings.returns([drawSettings, drawSettings])

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("20"), utils.parseEther("30")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("100"), utils.parseEther("600")]);

      const userNormalizedBalances = await drawCalculator.getNormalizedBalancesForDrawIds(wallet1.address, [1, 2])

      expect(userNormalizedBalances[0]).to.eq(utils.parseEther("0.2"))
      expect(userNormalizedBalances[1]).to.eq(utils.parseEther("0.05"))
    })

    it("reverts when totalSupply is zero", async () => {
      const timestamps = [42, 77]

      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
          ethers.utils.parseUnits("0.1", 9),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

      const draw1: Draw = newDraw({
        drawId: BigNumber.from(1),
        winningRandomNumber: BigNumber.from("1000"),
        timestamp: BigNumber.from(timestamps[0])
      })
      const draw2: Draw = newDraw({
        drawId: BigNumber.from(2),
        winningRandomNumber: BigNumber.from("1000"),
        timestamp: BigNumber.from(timestamps[1])
      })

      await drawHistory.mock.getDraws.returns([draw1, draw2])
      await drawSettingsHistory.mock.getDrawSettings.returns([drawSettings, drawSettings])

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("10"), utils.parseEther("30")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("0"), utils.parseEther("600")]);

      await expect(drawCalculator.getNormalizedBalancesForDrawIds(wallet1.address, [1, 2])).to.be.revertedWith("DrawCalc/total-supply-zero")
    })

    it("returns zero when the balance is very small", async () => {
      const timestamps = [42]

      const drawSettings: DrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseUnits("0.6", 9),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        startTimestampOffset: BigNumber.from(1),
        endTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)

      const draw1: Draw = newDraw({
        drawId: BigNumber.from(1),
        winningRandomNumber: BigNumber.from("1000"),
        timestamp: BigNumber.from(timestamps[0])
      })

      await drawHistory.mock.getDraws.returns([draw1])
      await drawSettingsHistory.mock.getDrawSettings.returns([drawSettings])


      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("0.000000000000000001")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("1000")]);

      const result = await drawCalculator.getNormalizedBalancesForDrawIds(wallet1.address, [1])

      expect(result[0]).to.eq(BigNumber.from(0))
    })

  })


  describe('calculate()', () => {
    const debug = newDebug('pt:DrawCalculator.test.ts:calculate()')

    context('with draw 1 set', () => {
      let drawSettings: DrawCalculatorSettings
      beforeEach(async () => {
        drawSettings = {
          distributions: [
            ethers.utils.parseUnits("0.8", 9),
            ethers.utils.parseUnits("0.2", 9),
          ],
          numberOfPicks: BigNumber.from("10000"),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
          startTimestampOffset: BigNumber.from(1),
          endTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001),
        };
        drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
        await drawSettingsHistory.mock.getDrawSettings.withArgs([1]).returns([drawSettings])
      })

      it('should calculate and win grand prize', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamps = [42];
        const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
        const ticketBalance = utils.parseEther('10');
        const totalSupply = utils.parseEther('100');

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): [balance]
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]);

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): [balance]
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]);

        const draw: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })
        await drawHistory.mock.getDraws.returns([draw])

        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw.drawId],
          pickIndices,
        )

        expect(prizesAwardable[0]).to.equal(utils.parseEther('80'));

        debug(
          'GasUsed for calculate(): ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw.drawId],
              pickIndices,
            )
          ).toString(),
        );
      });

      it('should revert with repeated pick indices', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamps = [42];
        const pickIndices = encoder.encode(['uint256[][]'], [[['1', '1']]]); // this isn't valid
        const ticketBalance = utils.parseEther('10');
        const totalSupply = utils.parseEther('100');

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): [balance]
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]);

        const draw: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })
        await drawHistory.mock.getDraws.returns([draw])

        await expect(
          drawCalculator.calculate(
            wallet1.address,
            [draw.drawId],
            pickIndices
          ),
        ).to.revertedWith('DrawCalc/picks-ascending');
      });

      it('can calculate 1000 picks', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamps = [42];

        const pickIndices = encoder.encode(['uint256[][]'], [[[...new Array<number>(1000).keys()]]]);
        const totalSupply = utils.parseEther("10000")
        const ticketBalance = utils.parseEther('1000'); // 10 percent of total supply
        // drawSettings.numberOfPicks = 10000 so user has 1000 picks

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): balance
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]);

        const draw: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })
        await drawHistory.mock.getDraws.returns([draw])

        debug(
          'GasUsed for calculate 1000 picks(): ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw.drawId],
              pickIndices,
            )
          ).toString(),
        );
      });

      it('should calculate for multiple picks, first pick grand prize winner, second pick no winnings', async () => {
        //function calculate(address user, uint256[] calldata randomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external override view returns (uint256){

        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamps = [42, 48];

        const pickIndices = encoder.encode(['uint256[][]'], [[['1'], ['2']]]);
        const ticketBalance = utils.parseEther('10');
        const ticketBalance2 = utils.parseEther('10');
        const totalSupply1 = utils.parseEther('100');
        const totalSupply2 = utils.parseEther('100');


        const draw1: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })
        const draw2: Draw = newDraw({ drawId: BigNumber.from(2), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[1]) })

        await drawHistory.mock.getDraws.returns([draw1, draw2])

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply1, totalSupply2]);

        const drawSettings2: DrawCalculatorSettings = {
          distributions: [ethers.utils.parseUnits("0.8", 9),
          ethers.utils.parseUnits("0.2", 9)],
          numberOfPicks: BigNumber.from(utils.parseEther('1')),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('20'),
          startTimestampOffset: BigNumber.from(1),
          endTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001),
        };
        drawSettings2.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)

        debug(`pushing settings for draw 2...`)

        await drawSettingsHistory.mock.getDrawSettings.withArgs([1, 2]).returns([drawSettings, drawSettings2]);

        debug(`PUSHED`)


        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw1.drawId, draw2.drawId],
          pickIndices,
        )

        expect(
          prizesAwardable[0]
        ).to.equal(utils.parseEther('80'));

        debug(
          'GasUsed for 2 calculate() calls: ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw1.drawId, draw2.drawId],
              pickIndices,
            )
          ).toString(),
        );

      });

      it('should not have enough funds for a second pick and revert', async () => {
        // the first draw the user has > 1 pick and the second draw has 0 picks (0.3/100 < 0.5 so rounds down to 0)
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamps = [42, 77];
        const totalSupply1 = utils.parseEther('100');
        const totalSupply2 = utils.parseEther('100');

        const pickIndices = encoder.encode(['uint256[][]'], [[['1'], ['2']]]);
        const ticketBalance = ethers.utils.parseEther('6'); // they had 6pc of all tickets

        const drawSettings: DrawCalculatorSettings = {
          distributions: [ethers.utils.parseUnits("0.8", 9),
          ethers.utils.parseUnits("0.2", 9)],
          numberOfPicks: BigNumber.from(1),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
          startTimestampOffset: BigNumber.from(1),
          endTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001),
        };
        drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

        const ticketBalance2 = ethers.utils.parseEther('0.3'); // they had 0.03pc of all tickets
        await ticket.mock.getAverageBalancesBetween
          .withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps)
          .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply1, totalSupply2]);

        const draw1: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })
        const draw2: Draw = newDraw({ drawId: BigNumber.from(2), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[1]) })

        await drawHistory.mock.getDraws.returns([draw1, draw2])

        await drawSettingsHistory.mock.getDrawSettings.withArgs([1, 2]).returns([drawSettings, drawSettings])

        await expect(
          drawCalculator.calculate(
            wallet1.address,
            [draw1.drawId, draw2.drawId],
            pickIndices
          ),
        ).to.revertedWith('DrawCalc/insufficient-user-picks');
      });

      it('should revert exceeding max user picks', async () => {
        // maxPicksPerUser is set to 2, user tries to claim with 3 picks
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamps = [42];
        const totalSupply1 = utils.parseEther('100');
        const pickIndices = encoder.encode(['uint256[][]'], [[['1', '2', '3']]]);
        const ticketBalance = ethers.utils.parseEther('6');

        const drawSettings: DrawCalculatorSettings = {
          distributions: [ethers.utils.parseUnits("0.8", 9),
          ethers.utils.parseUnits("0.2", 9)],
          numberOfPicks: BigNumber.from(1),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
          startTimestampOffset: BigNumber.from(1),
          endTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(2),
        };
        drawSettings.distributions = fillDrawSettingsDistributionsWithZeros(drawSettings.distributions)
        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween
          .withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps)
          .returns([ticketBalance]); // (user, timestamp): balance

        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply1]);

        const draw1: Draw = newDraw({ drawId: BigNumber.from(2), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) })

        await drawHistory.mock.getDraws.returns([draw1])

        await drawSettingsHistory.mock.getDrawSettings.withArgs([2]).returns([drawSettings])

        await expect(
          drawCalculator.calculate(
            wallet1.address,
            [draw1.drawId],
            pickIndices
          ),
        ).to.revertedWith('DrawCalc/exceeds-max-user-picks');
      });


      it('should calculate and win nothing', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet2.address]);
        const userRandomNumber = utils.solidityKeccak256(['bytes32', 'uint256'], [winningNumber, 1]);
        const timestamps = [42];
        const totalSupply = utils.parseEther('100');

        const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
        const ticketBalance = utils.parseEther('10');

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.startTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.endTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): balance
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]);

        const draw1: Draw = newDraw({ drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(userRandomNumber), timestamp: BigNumber.from(timestamps[0]) })

        await drawHistory.mock.getDraws.returns([draw1])

        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw1.drawId],
          pickIndices,
        )

        expect(
          prizesAwardable[0]
        ).to.equal(utils.parseEther('0'));
      });
    })
  });
});
