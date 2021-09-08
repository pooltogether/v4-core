import { ethers, artifacts } from 'hardhat';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { constants, Contract, ContractFactory } from 'ethers';
import { expect } from 'chai';
import { deploy1820 } from 'deploy-eip-1820'

const debug = require('debug')('ptv3:PoolEnv');
const now = () => (new Date().getTime() / 1000) | 0;
const toWei = (val: string | number) => ethers.utils.parseEther('' + val);
const { AddressZero } = constants;

describe('DrawBeacon', () => {
  let wallet: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let DrawBeaconFactory: ContractFactory
  let drawHistory: Contract;
  let drawBeacon: Contract;
  let drawBeacon2: Contract;
  let rng: MockContract;
  let registry: any;
  let rngFeeToken: MockContract;

  let rngRequestPeriodStart = now();
  let drawPeriodSeconds = 1000;

  const halfTime = drawPeriodSeconds / 2;
  const overTime = drawPeriodSeconds + 1;

  let IERC20;

  before(async () => {
    [wallet, wallet2] = await ethers.getSigners();
  });

  beforeEach(async () => {
    IERC20 = await artifacts.readArtifact('IERC20Upgradeable');

    debug(`using wallet ${wallet.address}`);

    debug(`deploy draw history...`);
    const DrawHistoryFactory = await ethers.getContractFactory('DrawHistory', wallet);
    drawHistory = await DrawHistoryFactory.deploy();

    debug(`initializing draw history...`);
    await drawHistory.initialize(wallet.address)

    debug('mocking rng...');
    const RNGInterface = await artifacts.readArtifact('RNGInterface');
    rng = await deployMockContract(wallet as Signer, RNGInterface.abi);
    rngFeeToken = await deployMockContract(wallet as Signer, IERC20.abi);

    await rng.mock.getRequestFee.returns(rngFeeToken.address, toWei('1'));

    debug('deploying drawBeacon...');
    DrawBeaconFactory = await ethers.getContractFactory('DrawBeaconHarness', wallet);
    drawBeacon = await DrawBeaconFactory.deploy();

    debug('initializing drawBeacon...');
    await drawBeacon.initialize(
      drawHistory.address,
      rng.address,
      rngRequestPeriodStart,
      drawPeriodSeconds,
    );

    debug('set draw history manager as draw beacon');
    await drawHistory.setManager(drawBeacon.address)
    debug('initialized!');
  });

  describe('initialize()', () => {
    it('should emit an Initialized event', async () => {
      debug('deploying another drawBeacon...');
      let drawBeacon2 = await DrawBeaconFactory.deploy();
      const initalizeResult2 = drawBeacon2.initialize(
        drawHistory.address,
        rng.address,
        rngRequestPeriodStart,
        drawPeriodSeconds
      );

      await expect(initalizeResult2)
        .to.emit(drawBeacon2, 'Initialized')
        .withArgs(
          drawHistory.address,
          rng.address,
          rngRequestPeriodStart,
          drawPeriodSeconds
        );
    });

    it('should set the params', async () => {
      expect(await drawBeacon.drawPeriodSeconds()).to.equal(drawPeriodSeconds);
      expect(await drawBeacon.rng()).to.equal(rng.address);
    });

    it('should reject rng request period', async () => {
      debug('deploying secondary drawBeacon...');
      drawBeacon2 = await DrawBeaconFactory.deploy();
      await expect(drawBeacon2.initialize(
        drawHistory.address,
        rng.address,
        0,
        drawPeriodSeconds
      )).to.be.revertedWith(
        'DrawBeacon/rng-request-period-greater-than-zero',
      );
    })

    it('should reject invalid rng', async () => {
      debug('deploying secondary drawBeacon...');
      drawBeacon2 = await DrawBeaconFactory.deploy();
      await expect(drawBeacon2.initialize(
        drawHistory.address,
        AddressZero,
        rngRequestPeriodStart,
        drawPeriodSeconds
      )).to.be.revertedWith(
        'DrawBeacon/rng-not-zero',
      );
    });
  });


  describe('estimateRemainingBlocksToPrize()', () => {
    it('should estimate using the constant', async () => {
      const ppr = await drawBeacon.drawPeriodRemainingSeconds();
      const blocks = parseInt('' + ppr.toNumber() / 14);
      expect(await drawBeacon.estimateRemainingBlocksToPrize(toWei('14'))).to.equal(blocks);
    });
  });

  describe('drawPeriodRemainingSeconds()', () => {
    it('should calculate the remaining seconds of the prize period', async () => {
      const startTime = await drawBeacon.drawPeriodStartedAt();

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.drawPeriodRemainingSeconds()).to.equal(halfTime);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.drawPeriodRemainingSeconds()).to.equal(0);
    });
  });

  describe('isDrawPeriodOver()', () => {
    it('should determine if the prize-period is over', async () => {
      const startTime = await drawBeacon.drawPeriodStartedAt();

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.isDrawPeriodOver()).to.equal(false);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.isDrawPeriodOver()).to.equal(true);
    });
  });

  describe('setRngService', () => {
    it('should only allow the owner to change it', async () => {
      await expect(drawBeacon.setRngService(wallet2.address))
        .to.emit(drawBeacon, 'RngServiceUpdated')
        .withArgs(wallet2.address);
    });

    it('should not allow anyone but the owner to change', async () => {
      const drawBeaconWallet2 = drawBeacon.connect(wallet2);
      await expect(drawBeaconWallet2.setRngService(wallet2.address)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should not be called if an rng request is in flight', async () => {
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('11', '1');
      await drawBeacon.setCurrentTime(await drawBeacon.drawPeriodEndAt());
      await drawBeacon.startDraw();

      await expect(drawBeacon.setRngService(wallet2.address)).to.be.revertedWith(
        'DrawBeacon/rng-in-flight',
      );
    });
  });

  describe('cancelDraw()', () => {
    it('should not allow anyone to cancel if the rng has not timed out', async () => {
      await expect(drawBeacon.cancelDraw()).to.be.revertedWith(
        'DrawBeacon/rng-not-timedout',
      );
    });

    it('should allow anyone to reset the rng if it times out', async () => {
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('11', '1');
      await drawBeacon.setCurrentTime(await drawBeacon.drawPeriodEndAt());

      await drawBeacon.startDraw();

      // set it beyond request timeout
      await drawBeacon.setCurrentTime(
        (await drawBeacon.drawPeriodEndAt())
          .add(await drawBeacon.rngRequestTimeout())
          .add(1),
      );

      // should be timed out
      expect(await drawBeacon.isRngTimedOut()).to.be.true;

      await expect(drawBeacon.cancelDraw())
        .to.emit(drawBeacon, 'DrawBeaconRNGRequestCancelled')
        .withArgs(wallet.address, 11, 1);
    });
  });

  describe('canStartRNGRequest()', () => {
    it('should determine if a prize is able to be awarded', async () => {
      const startTime = await drawBeacon.drawPeriodStartedAt();

      // Prize-period not over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(false);

      // Prize-period not over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(false);

      // Prize-period over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(drawPeriodSeconds));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(false);

      // Prize-period over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(drawPeriodSeconds));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(true);
    });
  });

  describe('canCompleteRNGRequest()', () => {
    it('should determine if a prize is able to be completed', async () => {
      // RNG not requested, RNG not completed
      await drawBeacon.setRngRequest(0, 0);
      await rng.mock.isRequestComplete.returns(false);
      expect(await drawBeacon.canCompleteRNGRequest()).to.equal(false);

      // RNG requested, RNG not completed
      await drawBeacon.setRngRequest(1, 100);
      await rng.mock.isRequestComplete.returns(false);
      expect(await drawBeacon.canCompleteRNGRequest()).to.equal(false);

      // RNG requested, RNG completed
      await drawBeacon.setRngRequest(1, 100);
      await rng.mock.isRequestComplete.returns(true);
      expect(await drawBeacon.canCompleteRNGRequest()).to.equal(true);
    });
  });

  describe('getLastRngLockBlock()', () => {
    it('should return the lock-block for the last RNG request', async () => {
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.getLastRngLockBlock()).to.equal(0);

      await drawBeacon.setRngRequest(1, 123);
      expect(await drawBeacon.getLastRngLockBlock()).to.equal(123);
    });
  });

  describe('getLastRngRequestId()', () => {
    it('should return the Request ID for the last RNG request', async () => {
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.getLastRngRequestId()).to.equal(0);

      await drawBeacon.setRngRequest(1, 123);
      expect(await drawBeacon.getLastRngRequestId()).to.equal(1);
    });
  });

  describe('_saveRNGRequestWithDraw()', () => {
    it('should succeed to create a new draw with provided random number and next block timestamp', async () => {
      const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      expect(
        await drawBeacon.saveRNGRequestWithDraw(
          1234567890,
        ),
      )
        .to.emit(drawHistory, 'DrawSet')
        .withArgs(
          0,
          0,
          currentTimestamp + 1,
          1234567890,
        );
    });
  });

  describe('completeDraw()', () => {
    it('should complete the rng request and push a new draw to DrawHistory', async () => {
      debug('Setting time');
      // ensure prize period is over
      await drawBeacon.setCurrentTime(await drawBeacon.drawPeriodEndAt());

      // allow an rng request
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('1', '1');

      debug('Starting rng request...');

      // start the rng request
      await drawBeacon.startDraw();

      // rng is done
      await rng.mock.isRequestComplete.returns(true);
      await rng.mock.randomNumber.returns(
        '0x6c00000000000000000000000000000000000000000000000000000000000000',
      );

      debug('Completing rng request...');

      let startedAt = await drawBeacon.drawPeriodStartedAt();

      // complete the rng request
      const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      expect(await drawBeacon.completeDraw())
        .to.emit(drawHistory, 'DrawSet')
        .withArgs(
          0,
          0,
          currentTimestamp + 1,
          '0x6c00000000000000000000000000000000000000000000000000000000000000',
        );

      expect(await drawBeacon.drawPeriodStartedAt()).to.equal(
        startedAt.add(drawPeriodSeconds),
      );
    });
  });

  describe('calculateNextDrawPeriodStartTime()', () => {
    it('should always sync to the last period start time', async () => {
      let startedAt = await drawBeacon.drawPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextDrawPeriodStartTime(
          startedAt.add(drawPeriodSeconds * 14),
        ),
      ).to.equal(startedAt.add(drawPeriodSeconds * 14));
    });

    it('should return the current if it is within', async () => {
      let startedAt = await drawBeacon.drawPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextDrawPeriodStartTime(
          startedAt.add(drawPeriodSeconds / 2),
        ),
      ).to.equal(startedAt);
    });

    it('should return the next if it is after', async () => {
      let startedAt = await drawBeacon.drawPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextDrawPeriodStartTime(
          startedAt.add(parseInt('' + drawPeriodSeconds * 1.5)),
        ),
      ).to.equal(startedAt.add(drawPeriodSeconds));
    });
  });

  describe('setDrawPeriodSeconds()', () => {
    it('should allow the owner to set the prize period', async () => {
      await expect(drawBeacon.setDrawPeriodSeconds(99))
        .to.emit(drawBeacon, 'RngRequestPeriodSecondsUpdated')
        .withArgs(99);

      expect(await drawBeacon.drawPeriodSeconds()).to.equal(99);
    });

    it('should not allow non-owners to set the prize period', async () => {
      await expect(drawBeacon.connect(wallet2).setDrawPeriodSeconds(99)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });
  });

  describe('with a prize-period scheduled in the future', () => {
    let drawBeaconBase2: Contract;

    beforeEach(async () => {
      rngRequestPeriodStart = 10000;

      debug('deploying secondary drawBeacon...');
      drawBeaconBase2 = await DrawBeaconFactory.deploy();

      debug('initializing secondary drawBeacon...');
      await drawBeaconBase2.initialize(
        drawHistory.address,
        rng.address,
        rngRequestPeriodStart,
        drawPeriodSeconds
      );

      debug('initialized!');
    });

    describe('startDraw()', () => {
      it('should prevent starting an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startDraw()).to.be.revertedWith(
          'DrawBeacon/prize-period-not-over',
        );
      });
    });

    describe('completeAward()', () => {
      it('should prevent completing an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startDraw()).to.be.revertedWith(
          'DrawBeacon/prize-period-not-over',
        );
      });
    });
  });
});
