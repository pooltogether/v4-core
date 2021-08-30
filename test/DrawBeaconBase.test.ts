// @ts-nocheck
import hre from 'hardhat';
import { deployMockContract } from 'ethereum-waffle';
import { deploy1820 } from 'deploy-eip-1820';
import { constants } from 'ethers';
import { expect } from 'chai';

const debug = require('debug')('ptv3:PoolEnv');
const now = () => (new Date().getTime() / 1000) | 0;
const toWei = (val) => ethers.utils.parseEther('' + val);

const { AddressZero } = constants;
const SENTINEL = '0x0000000000000000000000000000000000000001';
let overrides = { gasLimit: 9500000 };

describe('DrawBeaconBase', () => {
  let wallet, wallet2, wallet3, wallet4, wallet5;

  let registry, drawBeacon;

  let rng, rngFeeToken;

  let prizePeriodStart = now();
  let prizePeriodSeconds = 1000;

  let periodicPrizeStrategyListener;

  let IERC20, TokenListenerInterface;

  before(async () => {
    [wallet, wallet2, wallet3, wallet4, wallet5] = await hre.ethers.getSigners();
  });

  beforeEach(async () => {

    IERC20 = await hre.artifacts.readArtifact('IERC20Upgradeable');
    TokenListenerInterface = await hre.artifacts.readArtifact(
      'contracts/token/TokenListenerInterface.sol:TokenListenerInterface',
    );

    debug(`using wallet ${wallet.address}`);

    debug('deploying registry...');
    registry = await deploy1820(wallet);

    debug('mocking rng...');
    const RNGInterface = await hre.artifacts.readArtifact('RNGInterface');
    rng = await deployMockContract(wallet, RNGInterface.abi, overrides);

    rngFeeToken = await deployMockContract(wallet, IERC20.abi, overrides);

    const PeriodicPrizeStrategyListenerInterface = await hre.artifacts.readArtifact(
      'contracts/prize-strategy/PeriodicPrizeStrategyListenerInterface.sol:PeriodicPrizeStrategyListenerInterface',
    );

    periodicPrizeStrategyListener = await deployMockContract(
      wallet,
      PeriodicPrizeStrategyListenerInterface.abi,
      overrides,
    );

    await periodicPrizeStrategyListener.mock.supportsInterface.returns(true);
    await periodicPrizeStrategyListener.mock.supportsInterface
      .withArgs('0xffffffff')
      .returns(false);

    await rng.mock.getRequestFee.returns(rngFeeToken.address, toWei('1'));

    debug('deploying drawBeacon...');
    const DrawBeaconBaseHarness = await hre.ethers.getContractFactory(
      'DrawBeaconBaseHarness',
      wallet,
      overrides,
    );
    drawBeacon = await DrawBeaconBaseHarness.deploy();

    debug('initializing drawBeacon...');
    await drawBeacon.initialize(
      prizePeriodStart,
      prizePeriodSeconds,
      rng.address,
    );

    debug('initialized!');
  });

  describe('initialize()', () => {
    it('should emit an Initialized event', async () => {
      debug('deploying another drawBeacon...');
      const DrawBeaconBaseHarness = await hre.ethers.getContractFactory(
        'DrawBeaconBaseHarness',
        wallet,
        overrides,
      );

      let drawBeacon2 = await DrawBeaconBaseHarness.deploy();
      const initalizeResult2 = drawBeacon2.initialize(
        prizePeriodStart,
        prizePeriodSeconds,
        rng.address,
      );

      await expect(initalizeResult2)
        .to.emit(drawBeacon2, 'Initialized')
        .withArgs(
          prizePeriodStart,
          prizePeriodSeconds,
          rng.address,
        );
    });

    it('should set the params', async () => {
      expect(await drawBeacon.prizePeriodSeconds()).to.equal(prizePeriodSeconds);
      expect(await drawBeacon.rng()).to.equal(rng.address);
    });

    it('should reject invalid params', async () => {
      const _initArgs = [
        prizePeriodStart,
        prizePeriodSeconds,
        rng.address,
      ];
      let initArgs;

      debug('deploying secondary drawBeacon...');
      const DrawBeaconBaseHarness = await hre.ethers.getContractFactory(
        'DrawBeaconBaseHarness',
        wallet,
        overrides,
      );

      const drawBeacon2 = await DrawBeaconBaseHarness.deploy();

      debug('testing initialization of secondary drawBeacon...');

      initArgs = _initArgs.slice();
      initArgs[1] = 0;
      await expect(drawBeacon2.initialize(...initArgs)).to.be.revertedWith(
        'DrawBeaconBase/prize-period-greater-than-zero',
      );
      initArgs = _initArgs.slice();
      initArgs[2] = AddressZero;
      await expect(drawBeacon2.initialize(...initArgs)).to.be.revertedWith(
        'DrawBeaconBase/rng-not-zero',
      );
    });
  });

  describe('estimateRemainingBlocksToPrize()', () => {
    it('should estimate using the constant', async () => {
      let ppr = await drawBeacon.prizePeriodRemainingSeconds();
      let blocks = parseInt(ppr.toNumber() / 14);
      expect(await drawBeacon.estimateRemainingBlocksToPrize(toWei('14'))).to.equal(blocks);
    });
  });

  describe('prizePeriodRemainingSeconds()', () => {
    it('should calculate the remaining seconds of the prize period', async () => {
      const startTime = await drawBeacon.prizePeriodStartedAt();
      const halfTime = prizePeriodSeconds / 2;
      const overTime = prizePeriodSeconds + 1;

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.prizePeriodRemainingSeconds()).to.equal(halfTime);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.prizePeriodRemainingSeconds()).to.equal(0);
    });
  });

  describe('isPrizePeriodOver()', () => {
    it('should determine if the prize-period is over', async () => {
      const startTime = await drawBeacon.prizePeriodStartedAt();
      const halfTime = prizePeriodSeconds / 2;
      const overTime = prizePeriodSeconds + 1;

      // Half-time
      await drawBeacon.setCurrentTime(startTime.add(halfTime));
      expect(await drawBeacon.isPrizePeriodOver()).to.equal(false);

      // Over-time
      await drawBeacon.setCurrentTime(startTime.add(overTime));
      expect(await drawBeacon.isPrizePeriodOver()).to.equal(true);
    });
  });

  describe('setRngService', () => {
    it('should only allow the owner to change it', async () => {
      await expect(drawBeacon.setRngService(SENTINEL))
        .to.emit(drawBeacon, 'RngServiceUpdated')
        .withArgs(SENTINEL);
    });

    it('should not allow anyone but the owner to change', async () => {
      const drawBeaconWallet2 = drawBeacon.connect(wallet2);
      await expect(drawBeaconWallet2.setRngService(SENTINEL)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should not be called if an rng request is in flight', async () => {
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('11', '1');
      await drawBeacon.setCurrentTime(await drawBeacon.prizePeriodEndAt());
      await drawBeacon.startAward();

      await expect(drawBeacon.setRngService(SENTINEL)).to.be.revertedWith(
        'DrawBeaconBase/rng-in-flight',
      );
    });
  });

  describe('cancelAward()', () => {
    it('should not allow anyone to cancel if the rng has not timed out', async () => {
      await expect(drawBeacon.cancelAward()).to.be.revertedWith(
        'DrawBeaconBase/rng-not-timedout',
      );
    });

    it('should allow anyone to reset the rng if it times out', async () => {
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('11', '1');
      await drawBeacon.setCurrentTime(await drawBeacon.prizePeriodEndAt());

      await drawBeacon.startAward();

      // set it beyond request timeout
      await drawBeacon.setCurrentTime(
        (await drawBeacon.prizePeriodEndAt())
          .add(await drawBeacon.rngRequestTimeout())
          .add(1),
      );

      // should be timed out
      expect(await drawBeacon.isRngTimedOut()).to.be.true;

      await expect(drawBeacon.cancelAward())
        .to.emit(drawBeacon, 'DrawBeaconAwardCancelled')
        .withArgs(wallet.address, 11, 1);
    });
  });

  describe('canStartAward()', () => {
    it('should determine if a prize is able to be awarded', async () => {
      const startTime = await drawBeacon.prizePeriodStartedAt();

      // Prize-period not over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartAward()).to.equal(false);

      // Prize-period not over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(10));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartAward()).to.equal(false);

      // Prize-period over, RNG requested
      await drawBeacon.setCurrentTime(startTime.add(prizePeriodSeconds));
      await drawBeacon.setRngRequest(1, 100);
      expect(await drawBeacon.canStartAward()).to.equal(false);

      // Prize-period over, RNG not requested
      await drawBeacon.setCurrentTime(startTime.add(prizePeriodSeconds));
      await drawBeacon.setRngRequest(0, 0);
      expect(await drawBeacon.canStartAward()).to.equal(true);
    });
  });

  describe('canCompleteAward()', () => {
    it('should determine if a prize is able to be completed', async () => {
      // RNG not requested, RNG not completed
      await drawBeacon.setRngRequest(0, 0);
      await rng.mock.isRequestComplete.returns(false);
      expect(await drawBeacon.canCompleteAward()).to.equal(false);

      // RNG requested, RNG not completed
      await drawBeacon.setRngRequest(1, 100);
      await rng.mock.isRequestComplete.returns(false);
      expect(await drawBeacon.canCompleteAward()).to.equal(false);

      // RNG requested, RNG completed
      await drawBeacon.setRngRequest(1, 100);
      await rng.mock.isRequestComplete.returns(true);
      expect(await drawBeacon.canCompleteAward()).to.equal(true);
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
    let beforeAwardListener;

    beforeEach(async () => {
      const beforeAwardListenerStub = await hre.ethers.getContractFactory(
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
        'DrawBeaconBase/beforeAwardListener-invalid',
      );
    });

    it('should allow setting the listener to null', async () => {
      await expect(drawBeacon.setBeforeAwardListener(ethers.constants.AddressZero))
        .to.emit(drawBeacon, 'BeforeAwardListenerSet')
        .withArgs(ethers.constants.AddressZero);
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
      ).to.be.revertedWith('DrawBeaconBase/drawBeaconListener-invalid');
    });

    it('should allow setting the listener to null', async () => {
      await expect(drawBeacon.setDrawBeaconListener(ethers.constants.AddressZero))
        .to.emit(drawBeacon, 'DrawBeaconListenerSet')
        .withArgs(ethers.constants.AddressZero);
    });
  });

  describe('completeAward()', () => {
    it('should award the winner', async () => {
      debug('Setting time');

      // await distributor.mock.distribute
      //   .withArgs('48849787646992769944319009300540211125598274780817112954146168253338351566848')
      //   .returns();

      await drawBeacon.setDrawBeaconListener(periodicPrizeStrategyListener.address);
      await periodicPrizeStrategyListener.mock.afterPrizePoolAwarded
        .withArgs(
          '48849787646992769944319009300540211125598274780817112954146168253338351566848',
          await drawBeacon.prizePeriodStartedAt(),
        )
        .returns();

      // ensure prize period is over
      await drawBeacon.setCurrentTime(await drawBeacon.prizePeriodEndAt());

      // allow an rng request
      await rngFeeToken.mock.allowance.returns(0);
      await rngFeeToken.mock.approve.withArgs(rng.address, toWei('1')).returns(true);
      await rng.mock.requestRandomNumber.returns('1', '1');

      debug('Starting award...');

      // start the award
      await drawBeacon.startAward();

      // rng is done
      await rng.mock.isRequestComplete.returns(true);
      await rng.mock.randomNumber.returns(
        '0x6c00000000000000000000000000000000000000000000000000000000000000',
      );

      debug('Completing award...');

      let startedAt = await drawBeacon.prizePeriodStartedAt();

      // complete the award
      await drawBeacon.completeAward();

      expect(await drawBeacon.prizePeriodStartedAt()).to.equal(
        startedAt.add(prizePeriodSeconds),
      );
    });
  });

  describe('calculateNextPrizePeriodStartTime()', () => {
    it('should always sync to the last period start time', async () => {
      let startedAt = await drawBeacon.prizePeriodStartedAt();
      expect(
        await drawBeacon.calculateNextPrizePeriodStartTime(
          startedAt.add(prizePeriodSeconds * 14),
        ),
      ).to.equal(startedAt.add(prizePeriodSeconds * 14));
    });

    it('should return the current if it is within', async () => {
      let startedAt = await drawBeacon.prizePeriodStartedAt();
      expect(
        await drawBeacon.calculateNextPrizePeriodStartTime(
          startedAt.add(prizePeriodSeconds / 2),
        ),
      ).to.equal(startedAt);
    });

    it('should return the next if it is after', async () => {
      let startedAt = await drawBeacon.prizePeriodStartedAt();
      expect(
        await drawBeacon.calculateNextPrizePeriodStartTime(
          startedAt.add(parseInt(prizePeriodSeconds * 1.5)),
        ),
      ).to.equal(startedAt.add(prizePeriodSeconds));
    });
  });

  describe('setPrizePeriodSeconds()', () => {
    it('should allow the owner to set the prize period', async () => {
      await expect(drawBeacon.setPrizePeriodSeconds(99))
        .to.emit(drawBeacon, 'PrizePeriodSecondsUpdated')
        .withArgs(99);

      expect(await drawBeacon.prizePeriodSeconds()).to.equal(99);
    });

    it('should not allow non-owners to set the prize period', async () => {
      await expect(drawBeacon.connect(wallet2).setPrizePeriodSeconds(99)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });
  });

  describe('with a prize-period scheduled in the future', () => {
    let drawBeaconBase2;

    beforeEach(async () => {
      prizePeriodStart = 10000;

      debug('deploying secondary drawBeacon...');
      const DrawBeaconBaseHarness = await hre.ethers.getContractFactory(
        'DrawBeaconBaseHarness',
        wallet,
        overrides,
      );

      drawBeaconBase2 = await DrawBeaconBaseHarness.deploy();

      debug('initializing secondary drawBeacon...');
      await drawBeaconBase2.initialize(
        prizePeriodStart,
        prizePeriodSeconds,
        rng.address,
      );

      debug('initialized!');
    });

    describe('startAward()', () => {
      it('should prevent starting an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startAward()).to.be.revertedWith(
          'DrawBeaconBase/prize-period-not-over',
        );
      });
    });

    describe('completeAward()', () => {
      it('should prevent completing an award', async () => {
        await drawBeaconBase2.setCurrentTime(100);
        await expect(drawBeaconBase2.startAward()).to.be.revertedWith(
          'DrawBeaconBase/prize-period-not-over',
        );
      });
    });
  });
});
