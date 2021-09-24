import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, constants, Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { TsunamiDrawCalculatorSettings } from './types';
const { getSigners } = ethers;

describe('TsunamiDrawSettingsHistory', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;
  let drawSettingsHistory: Contract;

  const DRAW_SAMPLE_CONFIG = {
    timestamp: 1111111111,
    winningRandomNumber: 11111,
  };

  const drawSettings: TsunamiDrawCalculatorSettings = {
    matchCardinality: BigNumber.from(5),
    numberOfPicks: ethers.utils.parseEther('1'),
    distributions: [ethers.utils.parseUnits('0.5', 9)],
    bitRangeSize: BigNumber.from(3),
    prize: ethers.utils.parseEther('100'),
    drawStartTimestampOffset: BigNumber.from(0),
    drawEndTimestampOffset: BigNumber.from(3600),
    maxPicksPerUser: BigNumber.from(10)
  }

  function newDrawSettings(cardinality: number = 5): any {
    return {
      ...drawSettings,
      matchCardinality: BigNumber.from(cardinality)
    }
  }

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    const drawSettingsHistoryFactory: ContractFactory = await ethers.getContractFactory(
      'TsunamiDrawSettingsHistory',
    );

    drawSettingsHistory = await drawSettingsHistoryFactory.deploy(wallet1.address, 3);
    await drawSettingsHistory.setManager(wallet1.address);
  });

  describe('getNewestDrawSettings()', () => {
    it('should error when no draw history', async () => {
      await expect(drawSettingsHistory.getNewestDrawSettings()).to.be.revertedWith('DRB/future-draw')
    });

    it('should get the last draw after pushing a draw', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings(5))
      const settings = await drawSettingsHistory.getNewestDrawSettings();
      expect(settings.matchCardinality).to.equal(drawSettings.matchCardinality)
    });
  })

  describe('getOldestDrawSettings()', () => {
    it('should yield an empty draw when no history', async () => {
      const settings = await drawSettingsHistory.getOldestDrawSettings();
      expect(settings.matchCardinality).to.equal(0)
    });

    it('should yield the first draw when only one', async () => {
      await drawSettingsHistory.pushDrawSettings(2, newDrawSettings())
      const settings = await drawSettingsHistory.getOldestDrawSettings();
      expect(settings.matchCardinality).to.equal(drawSettings.matchCardinality)
    });

    it('should give the first draw when the buffer is not full', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings())
      await drawSettingsHistory.pushDrawSettings(1, newDrawSettings())
      const draw = await drawSettingsHistory.getOldestDrawSettings();
      expect(draw.matchCardinality).to.equal(drawSettings.matchCardinality)
    });

    it('should give the first draw when the buffer is full', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings())
      await drawSettingsHistory.pushDrawSettings(1, newDrawSettings())
      await drawSettingsHistory.pushDrawSettings(2, newDrawSettings())
      const draw = await drawSettingsHistory.getOldestDrawSettings();
      expect(draw.matchCardinality).to.equal(drawSettings.matchCardinality)
    });

    it('should give the oldest draw when the buffer has wrapped', async () => {
      // buffer can only hold 3, so the oldest should be draw 2
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings(4))
      await drawSettingsHistory.pushDrawSettings(1, newDrawSettings(5))
      await drawSettingsHistory.pushDrawSettings(2, newDrawSettings(6))
      await drawSettingsHistory.pushDrawSettings(3, newDrawSettings(7))
      await drawSettingsHistory.pushDrawSettings(4, newDrawSettings(8))
      const draw = await drawSettingsHistory.getOldestDrawSettings();
      expect(draw.matchCardinality).to.equal(6)
    });
  })

  describe('pushDrawSettings()', () => {
    context('sanity checks', () => {
      let drawSettings: TsunamiDrawCalculatorSettings

      beforeEach(async () => {
        drawSettings = {
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
          drawStartTimestampOffset: BigNumber.from(1),
          drawEndTimestampOffset: BigNumber.from(1),
          maxPicksPerUser: BigNumber.from(1001)
        };
      })

      it('should require a sane cardinality', async () => {
        drawSettings.matchCardinality = BigNumber.from(3)
        await expect(drawSettingsHistory.pushDrawSettings(1, drawSettings)).to.be.revertedWith("DrawCalc/matchCardinality-gte-distributions")
      })

      it('should require a sane bit range', async () => {
        drawSettings.matchCardinality = BigNumber.from(32) // means that bit range size max is 8
        drawSettings.bitRangeSize = BigNumber.from(9)
        await expect(drawSettingsHistory.pushDrawSettings(1, drawSettings)).to.be.revertedWith("DrawCalc/bitRangeSize-too-large")
      })

      it('cannot set over 100pc of prize for distribution', async () => {
        drawSettings.distributions[0] = ethers.utils.parseUnits('1', 9)
        await expect(drawSettingsHistory.pushDrawSettings(0, drawSettings)).to.be.revertedWith(
          'DrawCalc/distributions-gt-100%',
        );
      });

      it('cannot set bitRangeSize = 0', async () => {
        drawSettings.bitRangeSize = BigNumber.from(0)
        await expect(drawSettingsHistory.pushDrawSettings(0, drawSettings)).to.be.revertedWith(
          'DrawCalc/bitRangeSize-gt-0',
        );
      });

      it('cannot set maxPicksPerUser = 0', async () => {
        drawSettings.maxPicksPerUser = BigNumber.from(0)
        await expect(drawSettingsHistory.pushDrawSettings(0, drawSettings)).to.be.revertedWith(
          'DrawCalc/maxPicksPerUser-gt-0',
        );
      });
    })

    it('should fail to create a new draw when called from non-draw-manager', async () => {
      const claimableDrawWallet2 = drawSettingsHistory.connect(wallet2);
      await expect(claimableDrawWallet2.pushDrawSettings(0, newDrawSettings()))
        .to.be.revertedWith('Manageable/caller-not-manager-or-owner');
    });

    it('should create a new draw and emit DrawCreated', async () => {
      await expect(
        await drawSettingsHistory.pushDrawSettings(0, newDrawSettings())
      )
        .to.emit(drawSettingsHistory, 'DrawSettingsSet')
    });
  });

  describe('getDrawSetting()', () => {
    it('should read fail when no draw history', async () => {
      await expect(drawSettingsHistory.getDrawSetting(0)).to.revertedWith('DRB/future-draw');
    });

    it('should read the recently created draw struct', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings(6))
      const draw = await drawSettingsHistory.getDrawSetting(0);
      expect(draw.matchCardinality).to.equal(6);
    });
  });

  describe('getDrawSettings()', () => {
    it('should fail to read draws history is empty', async () => {
      await expect(drawSettingsHistory.getDrawSettings([0])).to.revertedWith('DRB/future-draw');
    });

    it('should successfully read an array of draws', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings(4))
      await drawSettingsHistory.pushDrawSettings(1, newDrawSettings(5))
      await drawSettingsHistory.pushDrawSettings(2, newDrawSettings(6))
      const draws = await drawSettingsHistory.getDrawSettings([0, 1, 2]);
      for (let index = 0; index < draws.length; index++) {
        expect(draws[index].matchCardinality).to.equal(index+4);
      }
    });
  });

  describe('setDrawSetting()', () => {
    it('should fail to set existing draw as unauthorized account', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings());
      await expect(drawSettingsHistory.connect(wallet3).setDrawSetting(0, newDrawSettings()))
        .to.be.revertedWith('Ownable/caller-not-owner')
    })

    it('should fail to set existing draw as manager ', async () => {
      await drawSettingsHistory.setManager(wallet2.address);
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings());
      await expect(drawSettingsHistory.connect(wallet2).setDrawSetting(0, newDrawSettings()))
        .to.be.revertedWith('Ownable/caller-not-owner')
    })

    it('should succeed to set existing draw as owner', async () => {
      await drawSettingsHistory.pushDrawSettings(0, newDrawSettings());
      await expect(drawSettingsHistory.setDrawSetting(0, newDrawSettings(6)))
        .to.emit(drawSettingsHistory, 'DrawSettingsSet')

      expect((await drawSettingsHistory.getDrawSetting(0)).matchCardinality).to.equal(6)
    });
  });
});
