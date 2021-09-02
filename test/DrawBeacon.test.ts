import { ethers, artifacts } from 'hardhat';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { constants, Contract } from 'ethers';
import { expect } from 'chai';

const debug = require('debug')('ptv3:PoolEnv');
const now = () => (new Date().getTime() / 1000) | 0;
const toWei = (val: string | number) => ethers.utils.parseEther('' + val);
const { AddressZero } = constants;
describe('DrawBeacon', () => {
  let wallet: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let drawHistory: Contract;
  let drawBeacon: Contract;
  let drawBeacon2: Contract;
  let rng: MockContract;
  let rngFeeToken: MockContract;
  let periodicPrizeStrategyListener: MockContract;

  let rngRequestPeriodStart = now();
  let rngRequestPeriodSeconds = 1000;

  const halfTime = rngRequestPeriodSeconds / 2;
  const overTime = rngRequestPeriodSeconds + 1;

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

    const PeriodicPrizeStrategyListenerInterface = await artifacts.readArtifact(
      'contracts/prize-strategy/PeriodicPrizeStrategyListenerInterface.sol:PeriodicPrizeStrategyListenerInterface',
    );
    periodicPrizeStrategyListener = await deployMockContract(wallet as Signer, PeriodicPrizeStrategyListenerInterface.abi);

    await periodicPrizeStrategyListener.mock.supportsInterface.returns(true);
    await periodicPrizeStrategyListener.mock.supportsInterface
      .withArgs('0xffffffff')
      .returns(false);

    await rng.mock.getRequestFee.returns(rngFeeToken.address, toWei('1'));

    debug('deploying drawBeacon...');
    const DrawBeaconHarness = await ethers.getContractFactory('DrawBeaconHarness', wallet);
    drawBeacon = await DrawBeaconHarness.deploy();

    debug('initializing drawBeacon...');
    await drawBeacon.initialize(
      drawHistory.address,
      rngRequestPeriodStart,
      rngRequestPeriodSeconds,
      rng.address,
    );

    debug('set draw history manager as draw beacon');
    await drawHistory.setManager(drawBeacon.address)
    debug('initialized!');
  });

  describe('initialize()', () => {
    it('should emit an Initialized event', async () => {
      debug('deploying another drawBeacon...');
      const DrawBeaconHarness = await ethers.getContractFactory(
        'DrawBeaconHarness',
        wallet
      );

      let drawBeacon2 = await DrawBeaconHarness.deploy();
      const initalizeResult2 = drawBeacon2.initialize(
        drawHistory.address,
        rngRequestPeriodStart,
        rngRequestPeriodSeconds,
        rng.address,
      );

      await expect(initalizeResult2)
        .to.emit(drawBeacon2, 'Initialized')
        .withArgs(
          drawHistory.address,
          rngRequestPeriodStart,
          rngRequestPeriodSeconds,
          rng.address,
        );
    });

    it('should set the params', async () => {
      expect(await drawBeacon.rngRequestPeriodSeconds()).to.equal(rngRequestPeriodSeconds);
      expect(await drawBeacon.rng()).to.equal(rng.address);
    });

    it('should reject invalid params', async () => {
      const _initArgs = [
        drawHistory.address,
        rngRequestPeriodStart,
        rngRequestPeriodSeconds,
        rng.address,
      ];
      let initArgs;

      debug('deploying secondary drawBeacon...');
      const DrawBeaconHarness = await ethers.getContractFactory(
        'DrawBeaconHarness',
        wallet,
      );

      drawBeacon2 = await DrawBeaconHarness.deploy();

      debug('testing initialization of secondary drawBeacon...');

      initArgs = _initArgs.slice();
      initArgs[2] = 0;
      await expect(drawBeacon2.initialize(...initArgs)).to.be.revertedWith(
        'DrawBeacon/rng-request-period-greater-than-zero',
      );
      initArgs = _initArgs.slice();
      initArgs[3] = AddressZero;
      await expect(drawBeacon2.initialize(...initArgs)).to.be.revertedWith(
        'DrawBeacon/rng-not-zero',
      );
    });
  });

  describe('estimateRemainingBlocksToPrize()', () => {
    it('should estimate using the constant', async () => {
      const ppr = await drawBeacon.rngRequestPeriodRemainingSeconds();
      const blocks = parseInt('' + ppr.toNumber() / 14);
      expect(await drawBeacon.estimateRemainingBlocksToPrize(toWei('14'))).to.equal(blocks);
    });
  });

  describe('rngRequestPeriodRemainingSeconds()', () => {
    it('should calculate the remaining seconds of the prize period', async () => {
      const startTime = await drawBeacon.rngRequestPeriodStartedAt();

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.rngRequestPeriodRemainingSeconds()).to.equal(halfTime);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.rngRequestPeriodRemainingSeconds()).to.equal(0);
    });
  });

  describe('isRngRequestPeriodOver()', () => {
    it('should determine if the prize-period is over', async () => {
      const startTime = await drawBeacon.rngRequestPeriodStartedAt();

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.isRngRequestPeriodOver()).to.equal(false);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.isRngRequestPeriodOver()).to.equal(true);
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
      await drawBeacon.setCurrentTime(await drawBeacon.rngRequestPeriodEndAt());
      await drawBeacon.startRNGRequest();

      await expect(drawBeacon.setRngService(wallet2.address)).to.be.revertedWith(
        'DrawBeacon/rng-in-flight',
      );
    });
  });

  describe('cancelRngRequest()', () => {
    it('should not allow anyone to cancel if the rng has not timed out', async () => {
      await expect(drawBeacon.cancelRngRequest()).to.be.revertedWith(
        'DrawBeacon/rng-not-timedout',
      );
    });

    it('should allow anyone to reset the rng if it times out', async () => {
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('11', '1');
      await drawBeacon.setCurrentTime(await drawBeacon.rngRequestPeriodEndAt());

      await drawBeacon.startRNGRequest();

      // set it beyond request timeout
      await drawBeacon.setCurrentTime(
        (await drawBeacon.rngRequestPeriodEndAt())
          .add(await drawBeacon.rngRequestTimeout())
          .add(1),
      );

      // should be timed out
      expect(await drawBeacon.isRngTimedOut()).to.be.true;

      await expect(drawBeacon.cancelRngRequest())
        .to.emit(drawBeacon, 'DrawBeaconRNGRequestCancelled')
        .withArgs(wallet.address, 11, 1);
    });
  });

  describe('canStartRNGRequest()', () => {
    it('should determine if a prize is able to be awarded', async () => {
      const startTime = await drawBeacon.rngRequestPeriodStartedAt();

      // Prize-period not over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(false);

      // Prize-period not over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(false);

      // Prize-period over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(rngRequestPeriodSeconds));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartRNGRequest()).to.equal(false);

      // Prize-period over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(rngRequestPeriodSeconds));
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

  describe('setBeforeAwardListener()', () => {
    let beforeAwardListener: Contract;

    beforeEach(async () => {
      const beforeAwardListenerStub = await ethers.getContractFactory(
        'BeforeAwardListenerStub',
      );
      beforeAwardListener = await beforeAwardListenerStub.deploy();
    });

    it('should allow the owner to change the listener', async () => {
      await expect(drawBeacon.setBeforeAwardListener(beforeAwardListener.address))
        .to.emit(drawBeacon, 'BeforeAwardListenerSet')
        .withArgs(beforeAwardListener.address);
    });

    it('should not allow anyone else to set it', async () => {
      await expect(
        drawBeacon.connect(wallet2).setBeforeAwardListener(beforeAwardListener.address),
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should not allow setting an EOA as a listener', async () => {
      await expect(drawBeacon.setBeforeAwardListener(wallet2.address)).to.be.revertedWith(
        'DrawBeacon/beforeAwardListener-invalid',
      );
    });

    it('should allow setting the listener to zero address', async () => {
      await expect(drawBeacon.setBeforeAwardListener(AddressZero))
        .to.emit(drawBeacon, 'BeforeAwardListenerSet')
        .withArgs(AddressZero);
    });
  });

  describe('setDrawBeaconListener()', () => {
    it('should allow the owner to change the listener', async () => {
      await expect(
        drawBeacon.setDrawBeaconListener(periodicPrizeStrategyListener.address),
      )
        .to.emit(drawBeacon, 'DrawBeaconListenerSet')
        .withArgs(periodicPrizeStrategyListener.address);
    });

    it('should not allow anyone else to set it', async () => {
      await expect(
        drawBeacon
          .connect(wallet2)
          .setDrawBeaconListener(periodicPrizeStrategyListener.address),
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should not allow setting an EOA as a listener', async () => {
      await expect(
        drawBeacon.setDrawBeaconListener(wallet2.address),
      ).to.be.revertedWith('DrawBeacon/drawBeaconListener-invalid');
    });

    it('should allow setting the listener to address zero', async () => {
      await expect(drawBeacon.setDrawBeaconListener(AddressZero))
        .to.emit(drawBeacon, 'DrawBeaconListenerSet')
        .withArgs(AddressZero);
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

  describe('completeRNGRequest()', () => {
    it('should complete the rng request and push a new draw to DrawHistory', async () => {
      debug('Setting time');

      await drawBeacon.setDrawBeaconListener(periodicPrizeStrategyListener.address);
      await periodicPrizeStrategyListener.mock.afterPrizePoolAwarded
        .withArgs(
          '48849787646992769944319009300540211125598274780817112954146168253338351566848',
          await drawBeacon.rngRequestPeriodStartedAt(),
        )
        .returns();

      // ensure prize period is over
      await drawBeacon.setCurrentTime(await drawBeacon.rngRequestPeriodEndAt());

      // allow an rng request
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('1', '1');

      debug('Starting rng request...');

      // start the rng request
      await drawBeacon.startRNGRequest();

      // rng is done
      await rng.mock.isRequestComplete.returns(true);
      await rng.mock.randomNumber.returns(
        '0x6c00000000000000000000000000000000000000000000000000000000000000',
      );

      debug('Completing rng request...');

      let startedAt = await drawBeacon.rngRequestPeriodStartedAt();

      // complete the rng request
      const currentTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      expect(await drawBeacon.completeRNGRequest())
        .to.emit(drawHistory, 'DrawSet')
        .withArgs(
          0,
          0,
          currentTimestamp + 1,
          '0x6c00000000000000000000000000000000000000000000000000000000000000',
        );

      expect(await drawBeacon.rngRequestPeriodStartedAt()).to.equal(
        startedAt.add(rngRequestPeriodSeconds),
      );
    });
  });

  describe('calculateNextRngRequestPeriodStartTime()', () => {
    it('should always sync to the last period start time', async () => {
      let startedAt = await drawBeacon.rngRequestPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextRngRequestPeriodStartTime(
          startedAt.add(rngRequestPeriodSeconds * 14),
        ),
      ).to.equal(startedAt.add(rngRequestPeriodSeconds * 14));
    });

    it('should return the current if it is within', async () => {
      let startedAt = await drawBeacon.rngRequestPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextRngRequestPeriodStartTime(
          startedAt.add(rngRequestPeriodSeconds / 2),
        ),
      ).to.equal(startedAt);
    });

    it('should return the next if it is after', async () => {
      let startedAt = await drawBeacon.rngRequestPeriodStartedAt();
      expect(
        await drawBeacon.calculateNextRngRequestPeriodStartTime(
          startedAt.add(parseInt('' + rngRequestPeriodSeconds * 1.5)),
        ),
      ).to.equal(startedAt.add(rngRequestPeriodSeconds));
    });
  });

  describe('setRngRequestPeriodSeconds()', () => {
    it('should allow the owner to set the prize period', async () => {
      await expect(drawBeacon.setRngRequestPeriodSeconds(99))
        .to.emit(drawBeacon, 'RngRequestPeriodSecondsUpdated')
        .withArgs(99);

      expect(await drawBeacon.rngRequestPeriodSeconds()).to.equal(99);
    });

    it('should not allow non-owners to set the prize period', async () => {
      await expect(drawBeacon.connect(wallet2).setRngRequestPeriodSeconds(99)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });
  });

  describe('with a prize-period scheduled in the future', () => {
    let drawBeaconBase2: Contract;

    beforeEach(async () => {
      rngRequestPeriodStart = 10000;

      debug('deploying secondary drawBeacon...');
      const DrawBeaconHarness = await ethers.getContractFactory(
        'DrawBeaconHarness',
        wallet
      );

      drawBeaconBase2 = await DrawBeaconHarness.deploy();

      debug('initializing secondary drawBeacon...');
      await drawBeaconBase2.initialize(
        drawHistory.address,
        rngRequestPeriodStart,
        rngRequestPeriodSeconds,
        rng.address,
      );

      debug('initialized!');
    });

    describe('startRNGRequest()', () => {
      it('should prevent starting an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startRNGRequest()).to.be.revertedWith(
          'DrawBeacon/prize-period-not-over',
        );
      });
    });

    describe('completeAward()', () => {
      it('should prevent completing an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startRNGRequest()).to.be.revertedWith(
          'DrawBeacon/prize-period-not-over',
        );
      });
    });
  });
});
