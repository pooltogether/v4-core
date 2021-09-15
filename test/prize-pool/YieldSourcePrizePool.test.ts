import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { constants, Contract, ContractFactory, utils } from 'ethers';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import hardhat from 'hardhat';

const { AddressZero, MaxUint256 } = constants;
const { parseEther: toWei } = utils;

const debug = require('debug')('ptv3:YieldSourcePrizePool.test');

describe('YieldSourcePrizePool', function () {
  let wallet: SignerWithAddress;
  let wallet2: SignerWithAddress;

  let prizePool: Contract;
  let depositToken: Contract;
  let yieldSource: MockContract;
  let ticket: Contract;
  let YieldSourcePrizePool: ContractFactory;

  let initializeTxPromise: Promise<any>;

  beforeEach(async () => {
    [wallet, wallet2] = await hardhat.ethers.getSigners();
    debug(`using wallet ${wallet.address}`);

    debug('creating token...');
    const ERC20MintableContract = await hardhat.ethers.getContractFactory('ERC20Mintable', wallet);
    depositToken = await ERC20MintableContract.deploy('Token', 'TOKE');

    debug('creating yield source mock...');
    const IYieldSource = await hardhat.artifacts.readArtifact('IYieldSource');
    yieldSource = await deployMockContract(wallet as Signer, IYieldSource.abi);
    yieldSource.mock.depositToken.returns(depositToken.address);

    debug('deploying YieldSourcePrizePool...');
    YieldSourcePrizePool = await hardhat.ethers.getContractFactory('YieldSourcePrizePool', wallet);
    prizePool = await YieldSourcePrizePool.deploy();

    const Ticket = await hardhat.ethers.getContractFactory('Ticket');
    ticket = await Ticket.deploy();
    await ticket.initialize('name', 'SYMBOL', 18, prizePool.address);

    initializeTxPromise = prizePool.initializeYieldSourcePrizePool(
      [ticket.address],
      yieldSource.address,
    );

    await initializeTxPromise;

    await prizePool.setPrizeStrategy(wallet2.address);
    await prizePool.setBalanceCap(ticket.address, MaxUint256);
  });

  describe('initialize()', () => {
    it('should initialize correctly', async () => {
      await expect(initializeTxPromise)
        .to.emit(prizePool, 'YieldSourcePrizePoolInitialized')
        .withArgs(yieldSource.address);

      expect(await prizePool.yieldSource()).to.equal(yieldSource.address);
    });

    it('should require the yield source', async () => {
      prizePool = await YieldSourcePrizePool.deploy();

      await expect(
        prizePool.initializeYieldSourcePrizePool(
          [ticket.address],
          AddressZero,
        ),
      ).to.be.revertedWith('YieldSourcePrizePool/yield-source-not-zero');
    });

    it('should require a valid yield source', async () => {
      prizePool = await YieldSourcePrizePool.deploy();

      await expect(
        prizePool.initializeYieldSourcePrizePool(
          [ticket.address],
          prizePool.address,
        ),
      ).to.be.revertedWith('YieldSourcePrizePool/invalid-yield-source');
    });
  });

  describe('supply()', async () => {
    it('should supply assets to the yield source', async () => {
      const amount = toWei('10');

      await yieldSource.mock.supplyTokenTo.withArgs(amount, prizePool.address).returns();

      await depositToken.approve(prizePool.address, amount);
      await depositToken.mint(wallet.address, amount);
      await prizePool.depositTo(wallet.address, amount, ticket.address);

      expect(await ticket.balanceOf(wallet.address)).to.equal(amount);
    });
  });

  describe('redeem()', async () => {
    it('should redeem assets from the yield source', async () => {
      const amount = toWei('99');

      await depositToken.approve(prizePool.address, amount);
      await depositToken.mint(wallet.address, amount);
      await yieldSource.mock.supplyTokenTo.withArgs(amount, prizePool.address).returns();
      await prizePool.depositTo(wallet.address, amount, ticket.address);

      await yieldSource.mock.redeemToken.withArgs(amount).returns(amount);
      await prizePool.withdrawFrom(
        wallet.address,
        amount,
        ticket.address,
      );

      expect(await ticket.balanceOf(wallet.address)).to.equal('0');
      expect(await depositToken.balanceOf(wallet.address)).to.equal(amount);
    });
  });

  describe('token()', async () => {
    it('should return the yield source token', async () => {
      expect(await prizePool.token()).to.equal(depositToken.address);
    });
  });

  describe('canAwardExternal()', async () => {
    it('should not allow the prize pool to award its token, as its likely the receipt', async () => {
      expect(await prizePool.canAwardExternal(yieldSource.address)).to.equal(false);
    });
  });
});
