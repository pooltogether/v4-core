import { expect } from 'chai';
import { ethers } from 'hardhat';
import { constants, Contract, ContractFactory } from 'ethers';
const { getSigners } = ethers;
const { AddressZero } = constants;
describe('DrawHistory', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let drawHistory: Contract;

  const DRAW_SAMPLE_CONFIG = {
    timestamp: 1111111111,
    winningRandomNumber: 11111,
  };

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    const drawHistoryFactory: ContractFactory = await ethers.getContractFactory(
      'DrawHistoryHarness',
    );
    drawHistory = await drawHistoryFactory.deploy();
    await drawHistory.initialize(wallet1.address);
  });


  describe('drawIdToDrawIndex()', () => {
    it('should fail get draw index with no draw history', async () => {
      await expect(drawHistory.drawIdToDrawIndex(0))
        .to.be.revertedWith('DrawHistory/no-draw-history')
    });

    it('should convert a draw id to a draw index with 32 draws', async () => {
      await drawHistory.addMultipleDraws(0, 32, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.winningRandomNumber);
      const drawIdToDrawIndex = await drawHistory.drawIdToDrawIndex(1);
      expect(drawIdToDrawIndex)
        .to.equal(1)
    });

    it('should convert a draw id to a draw index with 128 draws', async () => {
      await drawHistory.addMultipleDraws(0, 129, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.winningRandomNumber);
      const drawIdToDrawIndex = await drawHistory.drawIdToDrawIndex(128);
      expect(drawIdToDrawIndex)
        .to.equal(128)
    });

    it('should convert a draw id to a draw index with 257 draws', async () => {
      await drawHistory.addMultipleDraws(0, 128, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.winningRandomNumber);
      await drawHistory.addMultipleDraws(128, 258, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.winningRandomNumber);
      const drawIdToDrawIndex = await drawHistory.drawIdToDrawIndex(256);
      expect(drawIdToDrawIndex)
        .to.equal(0)
    });
  });

  describe('setManager()', () => {
    it('should fail to set draw manager from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = await drawHistory.connect(wallet2);
      await expect(claimableDrawUnauthorized.setManager(wallet2.address)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should fail to set draw manager with zero address', async () => {
      await expect(drawHistory.setManager(AddressZero)).to.be.revertedWith(
        'Manager/manager-not-zero-address',
      );
    });

    it('should fail to set draw manager with existing draw manager', async () => {
      await expect(drawHistory.setManager(wallet1.address)).to.be.revertedWith(
        'Manager/existing-manager-address',
      );
    });

    it('should succeed to set new draw manager', async () => {
      await expect(drawHistory.setManager(wallet2.address))
        .to.emit(drawHistory, 'ManagerTransferred')
        .withArgs(wallet2.address);
    });
  });

  describe('pushDraw()', () => {
    it('should fail to create a new draw when called from non-draw-manager', async () => {
      const claimableDrawWallet2 = drawHistory.connect(wallet2);
      await expect(
        claimableDrawWallet2.pushDraw(
          {
            drawId: 0,
            timestamp: DRAW_SAMPLE_CONFIG.timestamp,
            winningRandomNumber: DRAW_SAMPLE_CONFIG.winningRandomNumber
          }
        ),
      ).to.be.revertedWith('Manager/caller-not-manager-or-owner');
    });

    it('should create a new draw and emit DrawCreated', async () => {
      await expect(
        await drawHistory.pushDraw(
          {
            drawId: 0,
            timestamp: DRAW_SAMPLE_CONFIG.timestamp,
            winningRandomNumber: DRAW_SAMPLE_CONFIG.winningRandomNumber
          }
        ),
      )
        .to.emit(drawHistory, 'DrawSet')
        .withArgs(
          0,
          0,
          DRAW_SAMPLE_CONFIG.timestamp,
          DRAW_SAMPLE_CONFIG.winningRandomNumber,
        );
    });

    it('should create 8 new draws and return valid next draw id', async () => {
      for (let index = 0; index <= 8; index++) {
        await drawHistory.pushDraw(
          {
            drawId: index,
            timestamp: DRAW_SAMPLE_CONFIG.timestamp,
            winningRandomNumber: DRAW_SAMPLE_CONFIG.winningRandomNumber
          }
        )
      }
      expect(await drawHistory.nextDrawIndex())
        .to.equal(9)
      const currentDraw = await drawHistory.getDraw(8)
      expect(currentDraw.winningRandomNumber).to.equal(DRAW_SAMPLE_CONFIG.winningRandomNumber)
    });
  });

  describe('getDraw()', () => {
    it('should fail to read non-existent draw', async () => {
      await expect(drawHistory.getDraw(0)).to.revertedWith('DrawHistory/no-draw-history');
    });

    it('should read the recently created draw struct', async () => {
      await drawHistory.pushDraw(
        {
          drawId: 0,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp,
          winningRandomNumber: DRAW_SAMPLE_CONFIG.winningRandomNumber
        }
      );
      const draw = await drawHistory.getDraw(0);
      expect(draw.timestamp).to.equal(DRAW_SAMPLE_CONFIG.timestamp);
      expect(draw.winningRandomNumber).to.equal(DRAW_SAMPLE_CONFIG.winningRandomNumber);
      expect(draw.drawId).to.equal(0);
    });
  });

  describe('getDraws()', () => {
    it('should fail to read draw with no draw history', async () => {
      await expect(drawHistory.getDraws([0])).to.revertedWith('DrawHistory/no-draw-history');
    });

    it('should fail to read draws when final draw is is out of bounds ', async () => {
      await drawHistory.addMultipleDraws(0, 32, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.winningRandomNumber);
      await expect(drawHistory.getDraws([0, 1, 2, 32])).to.revertedWith('DrawHistory/drawid-out-of-bounds');
    });

    it('should succesfully read an array of draws', async () => {
      await drawHistory.addMultipleDraws(0, 32, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.winningRandomNumber);
      const draws = await drawHistory.getDraws([0, 1, 2, 3, 4, 5]);
      for (let index = 0; index < draws.length; index++) {
        expect(draws[index].timestamp).to.equal(DRAW_SAMPLE_CONFIG.timestamp);
        expect(draws[index].winningRandomNumber).to.equal(DRAW_SAMPLE_CONFIG.winningRandomNumber);
        expect(draws[index].drawId).to.equal(index);
      }
    });
  });

  describe('setDraw()', () => {
    it('should succeed to set existing draw', async () => {
      await drawHistory.pushDraw(
        {
          drawId: 0,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp,
          winningRandomNumber: DRAW_SAMPLE_CONFIG.winningRandomNumber
        }
      );
      const draw = await drawHistory.getDraw(0);
      expect(draw.timestamp).to.equal(DRAW_SAMPLE_CONFIG.timestamp);
      expect(draw.winningRandomNumber).to.equal(DRAW_SAMPLE_CONFIG.winningRandomNumber);
      expect(draw.drawId).to.equal(0);

      const DRAW_UPDATE_SAMPLE_CONFIG = {
        timestamp: 2222222222,
        winningRandomNumber: 22222,
      };
      await drawHistory.setDraw(
        0,
        {
          drawId: 0,
          timestamp: DRAW_UPDATE_SAMPLE_CONFIG.timestamp,
          winningRandomNumber: DRAW_UPDATE_SAMPLE_CONFIG.winningRandomNumber
        }
      )

      const drawUpdated = await drawHistory.getDraw(0);
      expect(drawUpdated.timestamp).to.equal(DRAW_UPDATE_SAMPLE_CONFIG.timestamp);
      expect(drawUpdated.winningRandomNumber).to.equal(DRAW_UPDATE_SAMPLE_CONFIG.winningRandomNumber);
      expect(drawUpdated.drawId).to.equal(0);
    });
  });
});
