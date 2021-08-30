import { expect } from 'chai';
import { constants, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { getSigners } = ethers;

describe('DrawHistory', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let drawHistory: Contract;

  const DRAW_SAMPLE_CONFIG = {
    randomNumber: 11111,
    timestamp: 1111111111,
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
    it('should convert a draw id to a draw index before reaching cardinality', async () => {
      const drawIdToDrawIndex = await drawHistory.drawIdToDrawIndex(1);
      expect(drawIdToDrawIndex)
        .to.equal(1)
    });

    it('should convert a draw id to a draw index after reaching cardinality', async () => {
      const drawIdToDrawIndex = await drawHistory.drawIdToDrawIndex(128);
      expect(drawIdToDrawIndex)
        .to.equal(128)
    });

    it('should convert a draw id to a draw index after reaching cardinality', async () => {
      const drawIdToDrawIndex = await drawHistory.drawIdToDrawIndex(256);
      expect(drawIdToDrawIndex)
        .to.equal(0)
    });
  });

  describe('setDrawManager()', () => {
    it('should fail to set draw manager from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = await drawHistory.connect(wallet2);
      await expect(claimableDrawUnauthorized.setDrawManager(wallet2.address)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should fail to set draw manager with zero address', async () => {
      await expect(drawHistory.setDrawManager(constants.AddressZero)).to.be.revertedWith(
        'DrawManager/draw-manager-not-zero-address',
      );
    });

    it('should fail to set draw manager with existing draw manager', async () => {
      await expect(drawHistory.setDrawManager(wallet1.address)).to.be.revertedWith(
        'DrawManager/existing-draw-manager-address',
      );
    });

    it('should succeed to set new draw manager', async () => {
      await expect(drawHistory.setDrawManager(wallet2.address))
        .to.emit(drawHistory, 'DrawManagerTransferred')
        .withArgs(wallet1.address, wallet2.address);
    });
  });

  describe('createDraw()', () => {
    it('should fail to create a new draw when called from non-draw-manager', async () => {
      const claimableDrawWallet2 = drawHistory.connect(wallet2);
      await expect(
        claimableDrawWallet2.createDraw(
          DRAW_SAMPLE_CONFIG.timestamp,
          DRAW_SAMPLE_CONFIG.randomNumber
        ),
      ).to.be.revertedWith('DrawManager/caller-not-draw-manager-or-owner');
    });

    it('should create a new draw and emit DrawCreated', async () => {
      await expect(
        await drawHistory.createDraw(
          DRAW_SAMPLE_CONFIG.timestamp,
          DRAW_SAMPLE_CONFIG.randomNumber,
        ),
      )
        .to.emit(drawHistory, 'DrawCreated')
        .withArgs(
          0,
          0,
          DRAW_SAMPLE_CONFIG.timestamp,
          DRAW_SAMPLE_CONFIG.randomNumber,
        );
    });

    it('should create 8 new draws and return valid next draw id', async () => {
      for (let index = 0; index <= 8; index++) {
        await drawHistory.createDraw(
          DRAW_SAMPLE_CONFIG.timestamp,
          DRAW_SAMPLE_CONFIG.randomNumber,
        )
      }
      expect(await drawHistory.nextDrawId())
        .to.equal(9)
      const nextDraw = await drawHistory.getDraw(8)
      expect(nextDraw.randomNumber).to.equal(DRAW_SAMPLE_CONFIG.randomNumber)
    });
  });

  describe('setDraw()', () => {
    it('should fail to set non-existent draw', async () => {
      const DRAW_UPDATE_SAMPLE_CONFIG = {
        randomNumber: 22222,
        timestamp: 2222222222,
      };
      await expect(drawHistory.setDraw(0, DRAW_UPDATE_SAMPLE_CONFIG.timestamp, DRAW_UPDATE_SAMPLE_CONFIG.randomNumber))
        .to.revertedWith('DrawHistory/draw-out-of-bounds');
    });

    it('should succeed to set existent draw', async () => {
      await drawHistory.createDraw(
        DRAW_SAMPLE_CONFIG.timestamp,
        DRAW_SAMPLE_CONFIG.randomNumber
      );
      const draw = await drawHistory.getDraw(0);
      expect(draw.timestamp).to.equal(DRAW_SAMPLE_CONFIG.timestamp);
      expect(draw.randomNumber).to.equal(DRAW_SAMPLE_CONFIG.randomNumber);
      expect(draw.drawId).to.equal(0);

      const DRAW_UPDATE_SAMPLE_CONFIG = {
        randomNumber: 22222,
        timestamp: 2222222222,
      };
      await drawHistory.setDraw(0, DRAW_UPDATE_SAMPLE_CONFIG.timestamp, DRAW_UPDATE_SAMPLE_CONFIG.randomNumber);

      const drawUpdated = await drawHistory.getDraw(0);
      expect(drawUpdated.timestamp).to.equal(DRAW_UPDATE_SAMPLE_CONFIG.timestamp);
      expect(drawUpdated.randomNumber).to.equal(DRAW_UPDATE_SAMPLE_CONFIG.randomNumber);
      expect(drawUpdated.drawId).to.equal(0);
    });
  });

  describe('getDraw()', () => {
    it('should fail to read non-existent draw', async () => {
      await expect(drawHistory.getDraw(0)).to.revertedWith('DrawHistory/draw-out-of-bounds');
    });

    it('should read the recently created draw struct which includes the current calculator', async () => {
      await drawHistory.createDraw(
        DRAW_SAMPLE_CONFIG.timestamp,
        DRAW_SAMPLE_CONFIG.randomNumber
      );
      const draw = await drawHistory.getDraw(0);
      expect(draw.timestamp).to.equal(DRAW_SAMPLE_CONFIG.timestamp);
      expect(draw.randomNumber).to.equal(DRAW_SAMPLE_CONFIG.randomNumber);
      expect(draw.drawId).to.equal(0);
    });
  });

});
