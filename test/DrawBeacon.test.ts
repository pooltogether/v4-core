import { ethers, artifacts } from 'hardhat';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { constants, Contract, ContractFactory, utils } from 'ethers';
import { expect } from 'chai';

const debug = require('debug')('pt:DrawBeacon.test.ts');

const now = () => (new Date().getTime() / 1000) | 0;

const { AddressZero } = constants;
const { parseEther: toWei } = utils;

describe.only('DrawBeacon', () => {
  let wallet: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let DrawBeaconFactory: ContractFactory
  let drawHistory: MockContract;
  let drawBeacon: Contract;
  let rng: MockContract;
  let rngFeeToken: MockContract;

  let beaconPeriodStart = now();
  const beaconPeriodSeconds = 1000;
  const nextDrawId = 1;

  const halfTime = beaconPeriodSeconds / 2;
  const overTime = beaconPeriodSeconds + 1;

  let IERC20;

  before(async () => {
    [wallet, wallet2] = await ethers.getSigners();
  });

  beforeEach(async () => {
    IERC20 = await artifacts.readArtifact('IERC20');

    debug(`using wallet ${wallet.address}`);

    debug(`deploy draw history...`);
    const DrawHistory = await artifacts.readArtifact('DrawHistory')
    drawHistory = await deployMockContract(wallet as Signer, DrawHistory.abi)

    debug('mocking rng...');
    const RNGInterface = await artifacts.readArtifact('RNGInterface');
    rng = await deployMockContract(wallet as Signer, RNGInterface.abi);
    rngFeeToken = await deployMockContract(wallet as Signer, IERC20.abi);

    await rng.mock.getRequestFee.returns(rngFeeToken.address, toWei('1'));

    debug('deploying drawBeacon...');
    DrawBeaconFactory = await ethers.getContractFactory('DrawBeaconHarness', wallet);
    drawBeacon = await DrawBeaconFactory.deploy(
      wallet.address,
      drawHistory.address,
      rng.address,
      nextDrawId,
      beaconPeriodStart,
      beaconPeriodSeconds
    );
  });

  describe('constructor()', () => {
    it('should emit a Deployed event', async () => {
      const drawBeacon2 = await DrawBeaconFactory.deploy(
        wallet.address,
        drawHistory.address,
        rng.address,
        nextDrawId,
        beaconPeriodStart,
        beaconPeriodSeconds
      );

      await expect(
        drawBeacon2.deployTransaction
      ).to.emit(drawBeacon2, 'Deployed')
        .withArgs(
          drawHistory.address,
          rng.address,
          nextDrawId,
          beaconPeriodStart,
          beaconPeriodSeconds
        );

      await expect(
        drawBeacon2.deployTransaction
      ).to.emit(drawBeacon2, 'BeaconPeriodStarted')
        .withArgs(
          wallet.address,
          beaconPeriodStart
        );
    });

    it('should set the params', async () => {
      expect(await drawBeacon.rng()).to.equal(rng.address);
      expect(await drawBeacon.beaconPeriodStartedAt()).to.equal(beaconPeriodStart);
      expect(await drawBeacon.beaconPeriodSeconds()).to.equal(beaconPeriodSeconds);
    });

    it('should reject rng request period', async () => {
      await expect(
        DrawBeaconFactory.deploy(
          wallet.address,
          drawHistory.address,
          rng.address,
          nextDrawId,
          0,
          beaconPeriodSeconds
        )
      ).to.be.revertedWith(
        'DrawBeacon/beacon-period-greater-than-zero',
      );
    })

    it('should reject invalid rng', async () => {
      await expect(
        DrawBeaconFactory.deploy(
          wallet.address,
          drawHistory.address,
          AddressZero,
          nextDrawId,
          beaconPeriodStart,
          beaconPeriodSeconds
        )
      ).to.be.revertedWith(
        'DrawBeacon/rng-not-zero',
      );
    });

    it('should reject nextDrawId inferior to 1', async () => {
      await expect(
        DrawBeaconFactory.deploy(
          wallet.address,
          drawHistory.address,
          rng.address,
          0,
          beaconPeriodStart,
          beaconPeriodSeconds
        )
      ).to.be.revertedWith(
        'DrawBeacon/next-draw-id-gte-one',
      );
    });
  });

  describe('beaconPeriodRemainingSeconds()', () => {
    it('should calculate the remaining seconds of the prize period', async () => {
      const startTime = await drawBeacon.beaconPeriodStartedAt();

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.beaconPeriodRemainingSeconds()).to.equal(halfTime);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.beaconPeriodRemainingSeconds()).to.equal(0);
    });
  });

  describe('isBeaconPeriodOver()', () => {
    it('should determine if the prize-period is over', async () => {
      const startTime = await drawBeacon.beaconPeriodStartedAt();

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.isBeaconPeriodOver()).to.equal(false);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.isBeaconPeriodOver()).to.equal(true);
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
        'Ownable/caller-not-owner',
      );
    });

    it('should not be called if an rng request is in flight', async () => {
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('11', '1');
      await drawBeacon.setCurrentTime(await drawBeacon.beaconPeriodEndAt());
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
      await drawBeacon.setCurrentTime(await drawBeacon.beaconPeriodEndAt());

      await drawBeacon.startDraw();

      // set it beyond request timeout
      await drawBeacon.setCurrentTime(
        (await drawBeacon.beaconPeriodEndAt())
          .add(await drawBeacon.rngTimeout())
          .add(1),
      );

      // should be timed out
      expect(await drawBeacon.isRngTimedOut()).to.be.true;

      await expect(drawBeacon.cancelDraw())
        .to.emit(drawBeacon, 'DrawCancelled')
        .withArgs(wallet.address, 11, 1);
    });
  });

  describe('canStartDraw()', () => {
    it('should determine if a prize is able to be awarded', async () => {
      const startTime = await drawBeacon.beaconPeriodStartedAt();

      // Prize-period not over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartDraw()).to.equal(false);

      // Prize-period not over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartDraw()).to.equal(false);

      // Prize-period over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(beaconPeriodSeconds));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartDraw()).to.equal(false);

      // Prize-period over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(beaconPeriodSeconds));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartDraw()).to.equal(true);
    });
  });

  describe('canCompleteDraw()', () => {
    it('should determine if a prize is able to be completed', async () => {
      // RNG not requested, RNG not completed
      await drawBeacon.setRngRequest(0, 0);
      await rng.mock.isRequestComplete.returns(false);
      expect(await drawBeacon.canCompleteDraw()).to.equal(false);

      // RNG requested, RNG not completed
      await drawBeacon.setRngRequest(1, 100);
      await rng.mock.isRequestComplete.returns(false);
      expect(await drawBeacon.canCompleteDraw()).to.equal(false);

      // RNG requested, RNG completed
      await drawBeacon.setRngRequest(1, 100);
      await rng.mock.isRequestComplete.returns(true);
      expect(await drawBeacon.canCompleteDraw()).to.equal(true);
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

  describe('completeDraw()', () => {
    beforeEach(async () => {
      debug('Setting time');
      // ensure prize period is over
      await drawBeacon.setCurrentTime(await drawBeacon.beaconPeriodEndAt());

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
    })

    it('should emit the events', async () => {
      debug('Completing rng request...');

      const beaconPeriodEndAt = await drawBeacon.beaconPeriodEndAt()
      const beaconPeriodStartedAt = await drawBeacon.beaconPeriodStartedAt()

      await drawHistory.mock.pushDraw.withArgs([
        '0x6c00000000000000000000000000000000000000000000000000000000000000',
        1,
        beaconPeriodEndAt,
        beaconPeriodStartedAt,
        beaconPeriodSeconds
      ]).returns(1)

      expect(await drawBeacon.completeDraw())
        .to.emit(drawBeacon, 'DrawCompleted')
        .withArgs(
          wallet.address,
          '0x6c00000000000000000000000000000000000000000000000000000000000000'
        )
        .and.to.emit(drawBeacon, 'BeaconPeriodStarted')
        .withArgs(
          wallet.address,
          beaconPeriodEndAt
        )

      expect(await drawBeacon.beaconPeriodStartedAt()).to.equal(beaconPeriodEndAt);
    });
  });

  describe('calculateNextBeaconPeriodStartTime()', () => {
    it('should always sync to the last period start time', async () => {
      let startedAt = await drawBeacon.beaconPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextBeaconPeriodStartTime(
          startedAt.add(beaconPeriodSeconds * 14),
        ),
      ).to.equal(startedAt.add(beaconPeriodSeconds * 14));
    });

    it('should return the current if it is within', async () => {
      let startedAt = await drawBeacon.beaconPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextBeaconPeriodStartTime(
          startedAt.add(beaconPeriodSeconds / 2),
        ),
      ).to.equal(startedAt);
    });

    it('should return the next if it is after', async () => {
      let startedAt = await drawBeacon.beaconPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextBeaconPeriodStartTime(
          startedAt.add(parseInt('' + beaconPeriodSeconds * 1.5)),
        ),
      ).to.equal(startedAt.add(beaconPeriodSeconds));
    });
  });

  describe('setDrawHistory()', () => {
    it('should allow the owner to set the draw history', async () => {
      await expect(drawBeacon.setDrawHistory(wallet2.address))
        .to.emit(drawBeacon, 'DrawHistoryTransferred')
        .withArgs(wallet2.address);

      expect(await drawBeacon.getDrawHistory()).to.equal(wallet2.address);
    });
  })

  describe('setRngTimeout()', () => {
    it('should prevent the owner from setting rngTimeout below 60', async () => {
      await expect(drawBeacon.setRngTimeout(55))
        .to.not.emit(drawBeacon, 'RngTimeoutSet')

      expect(await drawBeacon.rngTimeut()).to.equal(100);
    });
    it('should allow the owner to set the rngTimeout above 60', async () => {
      await expect(drawBeacon.setRngTimeout(100))
        .to.emit(drawBeacon, 'RngTimeoutSet')
        .withArgs(100);

      expect(await drawBeacon.rngTimeut()).to.equal(100);
    });
  })

  describe('setBeaconPeriodSeconds()', () => {
    it('should allow the owner to set the beacon period', async () => {
      await expect(drawBeacon.setBeaconPeriodSeconds(99))
        .to.emit(drawBeacon, 'BeaconPeriodSecondsUpdated')
        .withArgs(99);

      expect(await drawBeacon.beaconPeriodSeconds()).to.equal(99);
    });

    it('should not allow non-owners to set the prize period', async () => {
      await expect(drawBeacon.connect(wallet2).setBeaconPeriodSeconds(99)).to.be.revertedWith(
        'Ownable/caller-not-owner',
      );
    });
  });

  describe('with a prize-period scheduled in the future', () => {
    let drawBeaconBase2: Contract;

    beforeEach(async () => {
      beaconPeriodStart = 10000;

      drawBeaconBase2 = await DrawBeaconFactory.deploy(
        wallet.address,
        drawHistory.address,
        rng.address,
        nextDrawId,
        beaconPeriodStart,
        beaconPeriodSeconds
      );
    });

    describe('startDraw()', () => {
      it('should prevent starting an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startDraw()).to.be.revertedWith(
          'DrawBeacon/beacon-period-not-over',
        );
      });
    });

    describe('completeAward()', () => {
      it('should prevent completing an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startDraw()).to.be.revertedWith(
          'DrawBeacon/beacon-period-not-over',
        );
      });
    });

    describe('Internal Functions', () => {
      it('should return the internally set block.timestamp', async () => {
        await drawBeacon.setCurrentTime(100);
        await expect(await drawBeacon.currentTime())
          .to.equal(100)
      });

      it('should return current block.timestamp', async () => {
        const timestamp = (await ethers.provider.getBlock('latest')).timestamp
        expect(await drawBeacon._currentTimeInternal())
          .to.equal(timestamp)
      });
    });

  });
});
