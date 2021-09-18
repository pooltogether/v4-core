import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Draw, TsunamiDrawCalculatorSettings } from './types';

const { getSigners } = ethers;

const newDebug = require('debug')

export async function deployDrawCalculator(signer: any): Promise<Contract> {
  const drawCalculatorFactory = await ethers.getContractFactory(
    'TsunamiDrawCalculatorHarness',
    signer,
  );
  const drawCalculator: Contract = await drawCalculatorFactory.deploy();
  return drawCalculator;
}

function calculateNumberOfWinnersAtIndex(bitRangeSize: number, distributionIndex: number): number {
  // Prize Count = (2**bitRange)**(cardinality-numberOfMatches)
  // if not grand prize: - (2^bitRange)**(cardinality-numberOfMatches-1)

  let prizeCount = ((2 ** bitRangeSize) ** (distributionIndex))
  if(distributionIndex > 0) {
    prizeCount -=  (2 ** bitRangeSize) ** (distributionIndex -1);
  }
  return prizeCount;
}

function modifyTimestampsWithOffset(timestamps: number[], offset: number): number[] {
  return timestamps.map((timestamp :number) => timestamp - offset);
}


describe('TsunamiDrawCalculator', () => {
  let drawCalculator: Contract; let ticket: MockContract; let claimableDraw: MockContract;
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;

  const encoder = ethers.utils.defaultAbiCoder

  beforeEach(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
    drawCalculator = await deployDrawCalculator(wallet1);

    let ticketArtifact = await artifacts.readArtifact('Ticket');
    ticket = await deployMockContract(wallet1, ticketArtifact.abi);

    let claimableDrawArtifact = await artifacts.readArtifact('ClaimableDraw');
    claimableDraw = await deployMockContract(wallet1, claimableDrawArtifact.abi);

    await drawCalculator.initialize(ticket.address, wallet2.address, claimableDraw.address);
  });

  describe('initialize()', () => {
    let drawCalculator: Contract
    beforeEach(async () => {
      drawCalculator = await deployDrawCalculator(wallet1);
    })

    it('should require non-zero ticket', async () => {
      await expect(drawCalculator.initialize(ethers.constants.AddressZero, wallet2.address, claimableDraw.address)).to.be.revertedWith('DrawCalc/ticket-not-zero')
    })

    it('should require non-zero manager', async () => {
      await expect(drawCalculator.initialize(ticket.address, ethers.constants.AddressZero, claimableDraw.address)).to.be.revertedWith('Manager/manager-not-zero-address')
    })

    it('should require non-zero draw', async () => {
      await expect(drawCalculator.initialize(ticket.address, wallet2.address, ethers.constants.AddressZero)).to.be.revertedWith('DrawCalc/claimable-draw-not-zero-address')
    })
  })

  describe('setDrawSettings()', () => {
    it('should not allow anyone else to set', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from("100"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      await expect(drawCalculator.connect(wallet3).setDrawSettings(0, drawSettings)).to.be.revertedWith('Manager/caller-not-manager-or-owner')
    })

    it('onlyOwner can setPrizeSettings', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };

      
      await claimableDraw.mock.setDrawCalculator.withArgs(0, drawCalculator.address).returns(drawCalculator.address);

      expect(await drawCalculator.setDrawSettings(0, drawSettings)).to.emit(
        drawCalculator,
        'DrawSettingsSet',
      );

      await expect(drawCalculator.connect(wallet2).setDrawSettings(drawSettings)).to.be.reverted;
    });

    it('cannot set over 100pc of prize for distribution', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      await expect(drawCalculator.setDrawSettings(0, drawSettings)).to.be.revertedWith(
        'DrawCalc/distributions-gt-100%',
      );
    });

    it('cannot set bitRangeSize = 0', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(0),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      await expect(drawCalculator.setDrawSettings(0, drawSettings)).to.be.revertedWith(
        'DrawCalc/bitRangeSize-gt-0',
      );
    });

    it('cannot set maxPicksPerUser = 0', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(2),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(0),
      };
      await expect(drawCalculator.setDrawSettings(0, drawSettings)).to.be.revertedWith(
        'DrawCalc/maxPicksPerUser-gt-0',
      );
    });

    it('cannot set numberOfPicks = 0', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
          ethers.utils.parseEther('0.04')
        ],
        numberOfPicks: utils.parseEther("0"),
        bitRangeSize: BigNumber.from(1),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      await expect(drawCalculator.setDrawSettings(0, drawSettings)).to.be.revertedWith(
        'DrawCalc/numberOfPicks-gt-0',
      );
    });

  });

  describe('setClaimableDraw()', () => {
    it('onlyOwnerOrManager can set', async () => {
      await expect(drawCalculator.setClaimableDraw(claimableDraw.address)).to.emit(
        drawCalculator,
        'ClaimableDrawSet',
      );
      await expect(drawCalculator.connect(wallet3).setClaimableDraw(claimableDraw.address)).to.be.reverted;
    })

    it('cant set to zero address', async () => {
      await expect(drawCalculator.setClaimableDraw(ethers.constants.AddressZero)).to.be.revertedWith("DrawCalc/claimable-draw-not-zero-address");
    })
  })

  describe('calculateDistributionIndex()', () => {
    it('grand prize gets the full fraction at index 0', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const amount = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, BigNumber.from(0));
      expect(amount).to.equal(drawSettings.distributions[0]);
    })
    it('runner up gets part of the fraction at index 1', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const amount = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, BigNumber.from(1));

      const prizeCount = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), 1)
      const expectedPrizeFraction = drawSettings.distributions[1].div(prizeCount)
      expect(amount).to.equal(expectedPrizeFraction);
    })
    it('all distribution indexes', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.5'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1')
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      for(let numberOfMatches = 0; numberOfMatches < drawSettings.distributions.length; numberOfMatches++) {
        
        const distributionIndex = BigNumber.from(drawSettings.distributions.length - numberOfMatches - 1) // minus one because we start at 0
        const fraction = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, distributionIndex);

        let prizeCount = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), distributionIndex.toNumber())
        
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

    it('calculates the number of prizes at distribution index 0', async () => {
      const bitRangeSize = 3
      const result = await drawCalculator.numberOfPrizesForIndex(bitRangeSize, BigNumber.from(4));
      // (2 ^ 3) ^  4 - (2 ^ 3) ^ (4-1) = 4096 - 512 = 3584
      expect(result).to.equal(3584)
    })

    it('calculates the number of prizes at all distribution indices', async () => {
      let drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.5'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1')
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      for(let distributionIndex = 0; distributionIndex < drawSettings.distributions.length; distributionIndex++) {
        const result = await drawCalculator.numberOfPrizesForIndex(drawSettings.bitRangeSize, distributionIndex);
        const expectedNumberOfWinners = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), distributionIndex)
        expect(result).to.equal(expectedNumberOfWinners);
      }
    })

  })

  describe('calculatePrizeDistributionFraction()', () => {
    it('calculates distribution index 0', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      const winningRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70"
      const userRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70" // intentionally same as winning random number
      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(userRandomNumber, winningRandomNumber, bitMasks)
      // all numbers match so grand prize!
      expect(prizeDistributionIndex).to.eq(BigNumber.from(0))
    })

    it('calculates distribution index 1', async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
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
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(3),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
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
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(6),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(63)) // 111111
      expect(bitMasks[1]).to.eq(BigNumber.from(4032)) // 11111100000

    })

    it("creates correct 4 bit masks", async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(15)) // 1111
      expect(bitMasks[1]).to.eq(BigNumber.from(240)) // 11110000 

    })
  })

  describe("getDrawSettings()", () => {
    it("gets correct draw settings", async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("10")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      
      await claimableDraw.mock.setDrawCalculator.withArgs(70, drawCalculator.address).returns(drawCalculator.address);
      await drawCalculator.setDrawSettings(70, drawSettings);
      
      const result = await drawCalculator.getDrawSettings(70);
      
      expect(result.matchCardinality).to.equal(drawSettings.matchCardinality)
      expect(result.bitRangeSize).to.equal(drawSettings.bitRangeSize)
      expect(result.prize).to.equal(drawSettings.prize)
      expect(result.numberOfPicks).to.equal(drawSettings.numberOfPicks)
      expect(result.distributions.length).to.equal(drawSettings.distributions.length)
      for(let i =0; i < result.distributions.length; i++) {
        expect(result.distributions[i]).to.deep.equal(drawSettings.distributions[i])
      }
    })
  })

  describe("calculateNumberOfUserPicks()", () => {
    it("calculates the correct number of user picks", async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from("100"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const normalizedUsersBalance = utils.parseEther("0.05") // has 5% of the total supply
      const userPicks = await drawCalculator.calculateNumberOfUserPicks(drawSettings, normalizedUsersBalance)
      expect(userPicks).to.eq(BigNumber.from(5))
    })
    it("calculates the correct number of user picks", async () => {
      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const normalizedUsersBalance = utils.parseEther("0.1") // has 10% of the total supply
      const userPicks = await drawCalculator.calculateNumberOfUserPicks(drawSettings, normalizedUsersBalance)
      expect(userPicks).to.eq(BigNumber.from(10000)) // 10% of numberOfPicks
    })
  })

  describe("getNormalizedBalancesAt()", () => {
    it("calculates the correct normalized balance", async () => {
      const timestamps = [42,77]

      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("20"), utils.parseEther("30")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("100"), utils.parseEther("600")]); 
      
      const userNormalizedBalances = await drawCalculator.getNormalizedBalancesAt(wallet1.address, timestamps, [drawSettings, drawSettings])
    
      expect(userNormalizedBalances[0]).to.eq(utils.parseEther("0.2"))
      expect(userNormalizedBalances[1]).to.eq(utils.parseEther("0.05"))
    })
    
    it("reverts when totalSupply is zero", async () => {
      const timestamps = [42,77]

      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("10"), utils.parseEther("30")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("0"), utils.parseEther("600")]); 

      await expect(drawCalculator.getNormalizedBalancesAt(wallet1.address, timestamps, [drawSettings, drawSettings])).to.be.revertedWith("DrawCalc/total-supply-zero")
    })

    it("returns zero when the balance is very small", async () => {
      const timestamps = [42]

      const drawSettings: TsunamiDrawCalculatorSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
        ],
        numberOfPicks: BigNumber.from("100000"),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
        drawStartTimestampOffset: BigNumber.from(1),
        drawEndTimestampOffset: BigNumber.from(1),
        maxPicksPerUser: BigNumber.from(1001),
      };
      const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
      const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())

      await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("0.00000000000000001")]); // (user, timestamp): [balance]
      await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([utils.parseEther("1000")]); 
      const result = await drawCalculator.getNormalizedBalancesAt(wallet1.address, timestamps, [drawSettings, drawSettings])
      expect(result[0]).to.eq(BigNumber.from(0))
    })

  })


  describe('calculate()', () => {
    const debug = newDebug('pt:TsunamiDrawCalculator.test.ts:calculate()')

    context('with draw 0 set', () => {
      let drawSettings: TsunamiDrawCalculatorSettings
      beforeEach(async () => {
        drawSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from("10000"),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
          drawStartTimestampOffset: BigNumber.from(1),
          drawEndTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001),
        };
        await claimableDraw.mock.setDrawCalculator.withArgs(0, drawCalculator.address).returns(drawCalculator.address);
        await drawCalculator.setDrawSettings(0, drawSettings)
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

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        
        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): [balance]
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]); 


        const draw: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) }

        
        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw],
          pickIndices,
        )

        expect(prizesAwardable[0]).to.equal(utils.parseEther('80'));

        debug(
          'GasUsed for calculate(): ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw],
              pickIndices,
            )
          ).toString(),
        );
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

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawEndTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): balance
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]); 

        const draw: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0])}

        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw],
          pickIndices,
        )

        debug(
          'GasUsed for calculate 1000 picks(): ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw],
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


        const draw1: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) }
        const draw2: Draw = { drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[1]) }

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawEndTimestampOffset.toNumber())

        await claimableDraw.mock.setDrawCalculator.withArgs(1, drawCalculator.address).returns(drawCalculator.address);

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply1, totalSupply2]); 
        
        const drawSettings2: TsunamiDrawCalculatorSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from(utils.parseEther('1')),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('20'),
          drawStartTimestampOffset: BigNumber.from(1),
          drawEndTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001),
        };

        await drawCalculator.setDrawSettings(1, drawSettings2);


        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw1, draw2],
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
              [draw1, draw2],
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
        
        const drawSettings: TsunamiDrawCalculatorSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from(1),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
          drawStartTimestampOffset: BigNumber.from(1),
          drawEndTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001),
        };

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawEndTimestampOffset.toNumber())

        const ticketBalance2 = ethers.utils.parseEther('0.3'); // they had 0.03pc of all tickets
        await ticket.mock.getAverageBalancesBetween
          .withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps)
          .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance
        
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply1, totalSupply2]);   

        const draw1: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) }
        const draw2: Draw = { drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[1]) }
        
        await claimableDraw.mock.setDrawCalculator.withArgs(1, drawCalculator.address).returns(drawCalculator.address);
        await drawCalculator.setDrawSettings(1, drawSettings)

        await expect(
          drawCalculator.calculate(
            wallet1.address,
            [draw1, draw2],
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
        
        const drawSettings: DrawSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from(1),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
          drawStartTimestampOffset: BigNumber.from(1),
          drawEndTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(2),
        };
        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawEndTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween
          .withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps)
          .returns([ticketBalance]); // (user, timestamp): balance
        
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply1]);   

        const draw1: Draw = { drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamps[0]) }
        
        await claimableDraw.mock.setDrawCalculator.withArgs(1, drawCalculator.address).returns(drawCalculator.address);
        await drawCalculator.setDrawSettings(1, drawSettings)

        await expect(
          drawCalculator.calculate(
            wallet1.address,
            [draw1],
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

        const offsetStartTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawStartTimestampOffset.toNumber())
        const offsetEndTimestamps = modifyTimestampsWithOffset(timestamps, drawSettings.drawEndTimestampOffset.toNumber())

        await ticket.mock.getAverageBalancesBetween.withArgs(wallet1.address, offsetStartTimestamps, offsetEndTimestamps).returns([ticketBalance]); // (user, timestamp): balance
        await ticket.mock.getAverageTotalSuppliesBetween.withArgs(offsetStartTimestamps, offsetEndTimestamps).returns([totalSupply]);   


        const draw1: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(userRandomNumber), timestamp: BigNumber.from(timestamps[0]) }

        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw1],
          pickIndices,
        )

        expect(
          prizesAwardable[0]
        ).to.equal(utils.parseEther('0'));
      });
    })
  });
});
