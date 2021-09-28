import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { PrizeDistributionSettings } from './types';
import { fillPrizeDistributionsWithZeros } from './helpers/fillPrizeDistributionsWithZeros';

const { getSigners } = ethers;

describe('PrizeDistributionHistory', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;
  let prizeDistributionHistory: Contract;

  const prizeDistributions: PrizeDistributionSettings = {
    matchCardinality: BigNumber.from(5),
    numberOfPicks: ethers.utils.parseEther('1'),
    distributions: [ethers.utils.parseUnits('0.5', 9)],
    bitRangeSize: BigNumber.from(3),
    prize: ethers.utils.parseEther('100'),
    startTimestampOffset: BigNumber.from(0),
    endTimestampOffset: BigNumber.from(3600),
    maxPicksPerUser: BigNumber.from(10)
  }

  prizeDistributions.distributions = fillPrizeDistributionsWithZeros(prizeDistributions.distributions)

  function newPrizeDistributions(cardinality: number = 5): any {
    return {
      ...prizeDistributions,
      matchCardinality: BigNumber.from(cardinality)
    }
  }

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    const prizeDistributionHistoryFactory: ContractFactory = await ethers.getContractFactory(
      'PrizeDistributionHistory',
    );

    prizeDistributionHistory = await prizeDistributionHistoryFactory.deploy(wallet1.address, 3);
    prizeDistributions.distributions = fillPrizeDistributionsWithZeros(prizeDistributions.distributions)
    await prizeDistributionHistory.setManager(wallet1.address);
  });

  describe('getNewestPrizeDistributions()', () => {
    it('should error when no draw history', async () => {
      await expect(prizeDistributionHistory.getNewestPrizeDistributions()).to.be.revertedWith('DRB/future-draw')
    });

    it('should get the last draw after pushing a draw', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions(5))
      const settings = await prizeDistributionHistory.getNewestPrizeDistributions();
      expect(settings.prizeDistributions.matchCardinality).to.equal(prizeDistributions.matchCardinality)
      expect(settings.drawId).to.equal(1)
    });
  })

  describe('getOldestPrizeDistributions()', () => {
    it('should yield an empty draw when no history', async () => {
      const draw = await prizeDistributionHistory.getOldestPrizeDistributions();
      expect(draw.prizeDistributions.matchCardinality).to.equal(0)
      expect(draw.drawId).to.equal(0)
    });

    it('should yield the first draw when only one', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(5, newPrizeDistributions())
      const draw = await prizeDistributionHistory.getOldestPrizeDistributions();
      expect(draw.prizeDistributions.matchCardinality).to.equal(5)
      expect(draw.drawId).to.equal(5)
    });

    it('should give the first draw when the buffer is not full', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(7, newPrizeDistributions())
      await prizeDistributionHistory.pushPrizeDistributions(8, newPrizeDistributions())
      const draw = await prizeDistributionHistory.getOldestPrizeDistributions();
      expect(draw.prizeDistributions.matchCardinality).to.equal(prizeDistributions.matchCardinality)
      expect(draw.drawId).to.equal(7)
    });

    it('should give the first draw when the buffer is full', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(9, newPrizeDistributions(1))
      await prizeDistributionHistory.pushPrizeDistributions(10, newPrizeDistributions(2))
      await prizeDistributionHistory.pushPrizeDistributions(11, newPrizeDistributions(3))
      const draw = await prizeDistributionHistory.getOldestPrizeDistributions();
      expect(draw.prizeDistributions.matchCardinality).to.equal(1)
      expect(draw.drawId).to.equal(9)
    });

    it('should give the oldest draw when the buffer has wrapped', async () => {
      // buffer can only hold 3, so the oldest should be drawId 14
      await prizeDistributionHistory.pushPrizeDistributions(12, newPrizeDistributions(4))
      await prizeDistributionHistory.pushPrizeDistributions(13, newPrizeDistributions(5))
      await prizeDistributionHistory.pushPrizeDistributions(14, newPrizeDistributions(6))
      await prizeDistributionHistory.pushPrizeDistributions(15, newPrizeDistributions(7))
      await prizeDistributionHistory.pushPrizeDistributions(16, newPrizeDistributions(8))
      const draw = await prizeDistributionHistory.getOldestPrizeDistributions();
      expect(draw.prizeDistributions.matchCardinality).to.equal(6)
      expect(draw.drawId).to.equal(14)
    });

    // @TODO: Create PrizeDistributionHistory harness smart contract to expose
    describe('_estimateDrawId()', () => {
      it('should return Draw ID 0 when no history', async () => {

      });
    })
  })

  describe('pushPrizeDistributions()', () => {
    context('sanity checks', () => {
      let prizeDistributions: PrizeDistributionSettings

      beforeEach(async () => {
        prizeDistributions = {
          matchCardinality: BigNumber.from(5),
          distributions: [
            ethers.utils.parseUnits('0.6', 9),
            ethers.utils.parseUnits('0.1', 9),
            ethers.utils.parseUnits('0.1', 9),
            ethers.utils.parseUnits('0.1', 9),
          ],
          numberOfPicks: BigNumber.from("100"),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('1'),
          startTimestampOffset: BigNumber.from(1),
          endTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001)
        };
        prizeDistributions.distributions = fillPrizeDistributionsWithZeros(prizeDistributions.distributions)
      })

      it('should require a sane cardinality', async () => {
        prizeDistributions.matchCardinality = BigNumber.from(3)
        await expect(prizeDistributionHistory.pushPrizeDistributions(1, prizeDistributions)).to.be.revertedWith("DrawCalc/matchCardinality-gte-distributions")
      })

      it('should require a sane bit range', async () => {
        prizeDistributions.matchCardinality = BigNumber.from(32) // means that bit range size max is 8
        prizeDistributions.bitRangeSize = BigNumber.from(9)
        await expect(prizeDistributionHistory.pushPrizeDistributions(1, prizeDistributions)).to.be.revertedWith("DrawCalc/bitRangeSize-too-large")
      })

      it('cannot set over 100pc of prize for distribution', async () => {
        prizeDistributions.distributions[0] = ethers.utils.parseUnits('1', 9)
        await expect(prizeDistributionHistory.pushPrizeDistributions(1, prizeDistributions)).to.be.revertedWith(
          'DrawCalc/distributions-gt-100%',
        );
      });

      it('cannot set bitRangeSize = 0', async () => {
        prizeDistributions.bitRangeSize = BigNumber.from(0)
        await expect(prizeDistributionHistory.pushPrizeDistributions(1, prizeDistributions)).to.be.revertedWith(
          'DrawCalc/bitRangeSize-gt-0',
        );
      });

      it('cannot set maxPicksPerUser = 0', async () => {
        prizeDistributions.maxPicksPerUser = BigNumber.from(0)
        await expect(prizeDistributionHistory.pushPrizeDistributions(1, prizeDistributions)).to.be.revertedWith(
          'DrawCalc/maxPicksPerUser-gt-0',
        );
      });

    })

    it('should fail to create a new draw when called from non-draw-manager', async () => {
      const drawPrizeWallet2 = prizeDistributionHistory.connect(wallet2);
      await expect(drawPrizeWallet2.pushPrizeDistributions(1, newPrizeDistributions()))
        .to.be.revertedWith('Manageable/caller-not-manager-or-owner');
    });

    it('should create a new draw and emit DrawCreated', async () => {
      await expect(
        await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions())
      )
        .to.emit(prizeDistributionHistory, 'PrizeDistributionsSet')
    });
  });

  describe('getPrizeDistribution()', () => {
    it('should read fail when no draw history', async () => {
      await expect(prizeDistributionHistory.getPrizeDistribution(0)).to.revertedWith('DRB/future-draw');
    });

    it('should read the recently created draw struct', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions(6))
      const draw = await prizeDistributionHistory.getPrizeDistribution(1);
      expect(draw.matchCardinality).to.equal(6);
    });
  });

  describe('getPrizeDistributions()', () => {
    it('should fail to read if draws history is empty', async () => {
      await expect(prizeDistributionHistory.getPrizeDistributions([0])).to.revertedWith('DRB/future-draw');
    });

    it('should successfully read an array of draws', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions(4))
      await prizeDistributionHistory.pushPrizeDistributions(2, newPrizeDistributions(5))
      await prizeDistributionHistory.pushPrizeDistributions(3, newPrizeDistributions(6))
      const draws = await prizeDistributionHistory.getPrizeDistributions([1, 2, 3]);
      for (let index = 0; index < draws.length; index++) {
        expect(draws[index].matchCardinality).to.equal(index + 4);
      }
    });
  });

  describe('setPrizeDistribution()', () => {
    it('should fail to set existing draw as unauthorized account', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions());
      await expect(prizeDistributionHistory.connect(wallet3).setPrizeDistribution(1, newPrizeDistributions()))
        .to.be.revertedWith('Ownable/caller-not-owner')
    })

    it('should fail to set existing draw as manager ', async () => {
      await prizeDistributionHistory.setManager(wallet2.address);
      await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions());
      await expect(prizeDistributionHistory.connect(wallet2).setPrizeDistribution(1, newPrizeDistributions()))
        .to.be.revertedWith('Ownable/caller-not-owner')
    })

    it('should succeed to set existing draw as owner', async () => {
      await prizeDistributionHistory.pushPrizeDistributions(1, newPrizeDistributions());
      await expect(prizeDistributionHistory.setPrizeDistribution(1, newPrizeDistributions(6)))
        .to.emit(prizeDistributionHistory, 'PrizeDistributionsSet')

      expect((await prizeDistributionHistory.getPrizeDistribution(1)).matchCardinality).to.equal(6)
    });
  });
});
