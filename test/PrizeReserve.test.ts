import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { ethers, artifacts } from 'hardhat';
import { Artifact } from 'hardhat/types';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract, ContractFactory } from 'ethers';

import { increaseTime as increaseTimeHelper } from './helpers/increaseTime';

const { constants, getSigners, provider, utils } = ethers;
const debug = require('debug')('ptv4:PrizeReserve');

const { AddressZero } = constants;
const { getBlock } = provider;
const { parseEther: toWei } = utils;

const increaseTime = (time: number) => increaseTimeHelper(provider, time);

describe('PrizeReserve', () => {
  let contractsOwner: SignerWithAddress;
  let wallet2: SignerWithAddress;

  let prizeReserve: Contract;
  let sponsorship: Contract;
  let ticket: Contract;

  let prizePoolArtifact: Artifact;
  let prizePool: MockContract;

  let prizeReserveFactory: ContractFactory;
  let erc20MintableFactory: ContractFactory;

  before(async () => {
    [contractsOwner, wallet2] = await getSigners();

    prizeReserveFactory = await ethers.getContractFactory('PrizeReserve');

    erc20MintableFactory = await ethers.getContractFactory('ERC20Mintable');

    prizePoolArtifact = await artifacts.readArtifact('PrizePool');
  });

  beforeEach(async () => {
    debug('mocking ticket, sponsorship and prizePool...');
    sponsorship = await erc20MintableFactory.deploy('Sponsorship', 'SPON');
    ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');

    prizePool = await deployMockContract(contractsOwner as Signer, prizePoolArtifact.abi);

    await prizePool.mock.tokens.returns([ticket.address, sponsorship.address]);

    debug('deploy PrizeReserve...');
    prizeReserve = await prizeReserveFactory.deploy(prizePool.address);
  });

  describe('checkpoint()', () => {
    it('should record a new twab when balance changes', async () => {
      const amount = toWei('100');

      await sponsorship.mint(contractsOwner.address, amount);
      await sponsorship.transfer(prizeReserve.address, amount);

      await increaseTime(10);

      const firstCheckpointTx = await prizeReserve.checkpoint();
      const { timestamp: firstTimestamp } = await getBlock(firstCheckpointTx.transactionHash);

      expect(firstCheckpointTx)
        .to.emit(prizeReserve, 'NewBalanceTwab')
        .withArgs([toWei('0'), firstTimestamp]);

      expect(await prizeReserve.getBalanceAt(firstTimestamp)).to.equal(amount);
    });

    it('should emit NewBalanceTwab only once if transactions happen in the same block', async () => {
      const amount = toWei('100');
      const totalAmount = amount.mul(2);

      await sponsorship.mint(contractsOwner.address, totalAmount);
      await sponsorship.transfer(prizeReserve.address, amount);

      await increaseTime(10);

      const firstCheckpointTx = await prizeReserve.checkpoint();
      const { timestamp: firstTimestamp } = await getBlock(firstCheckpointTx.transactionHash);

      await sponsorship.transfer(prizeReserve.address, amount);

      await increaseTime(-2);

      const secondCheckpointTx = await prizeReserve.checkpoint();
      const { timestamp: secondTimestamp } = await getBlock(secondCheckpointTx.transactionHash);

      expect(firstCheckpointTx)
        .to.emit(prizeReserve, 'NewBalanceTwab')
        .withArgs([toWei('0'), firstTimestamp]);

      expect(secondCheckpointTx)
        .to.not.emit(prizeReserve, 'NewBalanceTwab')
        .withArgs([amount, secondTimestamp]);

      expect(await prizeReserve.getBalanceAt(firstTimestamp)).to.equal(totalAmount);
      expect(await prizeReserve.getBalanceAt(secondTimestamp)).to.equal(totalAmount);
    });
  })

  describe('getBalance()', () => {
    const amount = toWei('100');

    beforeEach(async () => {
      await sponsorship.mint(contractsOwner.address, amount);
      await sponsorship.transfer(prizeReserve.address, amount);
    });

    it('should return current balance', async () => {
      expect(await prizeReserve.getBalance()).to.equal(amount);
    });

    it('should return current balance after a withdrawal', async () => {
      const withdrawalAmount = toWei('50');

      await prizeReserve.withdraw(wallet2.address, withdrawalAmount);

      expect(await prizeReserve.getBalance()).to.equal(amount.sub(withdrawalAmount));
      expect(await sponsorship.balanceOf(wallet2.address)).to.equal(withdrawalAmount);
    });
  });

  describe('getBalanceAt()', () => {
    let timestampAfterFirstCheckpoint: number;

    beforeEach(async () => {
      await prizeReserve.checkpoint();

      timestampAfterFirstCheckpoint = (await provider.getBlock('latest')).timestamp;

      await sponsorship.mint(contractsOwner.address, toWei('1000'));
      await sponsorship.transfer(prizeReserve.address, toWei('100')); // balance is now equal to 100
    });

    it('should return balance at timestamp', async () => {
      await prizeReserve.checkpoint();

      const timestampAfterSecondCheckpoint = (await provider.getBlock('latest')).timestamp;

      await increaseTime(10);

      await prizeReserve.withdraw(wallet2.address, toWei('50')); // balance is now equal to 50

      await increaseTime(10);

      await prizeReserve.checkpoint();

      const timestampAfterThirdCheckpoint = (await provider.getBlock('latest')).timestamp;

      await sponsorship.transfer(prizeReserve.address, toWei('100')); // balance is now equal to 150

      await increaseTime(10);

      await prizeReserve.checkpoint();

      const timestampAfterFourthCheckpoint = (await provider.getBlock('latest')).timestamp;

      await sponsorship.transfer(prizeReserve.address, toWei('500')); // balance is now equal to 650

      await increaseTime(10);

      await prizeReserve.checkpoint();

      const timestampAfterFifthCheckpoint = (await provider.getBlock('latest')).timestamp;

      expect(await prizeReserve.getBalanceAt(timestampAfterFirstCheckpoint)).to.equal(toWei('0'));
      expect(await prizeReserve.getBalanceAt(timestampAfterSecondCheckpoint)).to.equal(toWei('100'));
      expect(await prizeReserve.getBalanceAt(timestampAfterThirdCheckpoint)).to.equal(toWei('50'));
      expect(await prizeReserve.getBalanceAt(timestampAfterFourthCheckpoint)).to.equal(toWei('150'));
      expect(await prizeReserve.getBalanceAt(timestampAfterFifthCheckpoint)).to.equal(toWei('650'));
    });
  });

  describe('withdraw()', () => {
    const amount = toWei('100');

    beforeEach(async () => {
      await sponsorship.mint(contractsOwner.address, amount);
      await sponsorship.transfer(prizeReserve.address, amount);
    });

    it('should withdraw and record a new TWAB', async () => {
      const withdrawalAmount = toWei('50');

      const withdrawalTx = await prizeReserve.withdraw(wallet2.address, withdrawalAmount);
      const { timestamp } = await getBlock(withdrawalTx.transactionHash);

      expect(withdrawalTx)
        .to.emit(prizeReserve, 'NewWithdrawalTwab')
        .withArgs([toWei('0'), timestamp]);

      expect(withdrawalTx)
        .to.emit(prizeReserve, 'Withdrawn')
        .withArgs(contractsOwner.address, wallet2.address, withdrawalAmount);
    });

    it('should emit NewWithdrawalTwab event only once if transactions happen in the same block', async () => {
      const withdrawalAmount = toWei('50');

      const withdrawalTx = await prizeReserve.withdraw(wallet2.address, withdrawalAmount);

      await increaseTime(-1);

      const secondWithdrawalTx = await prizeReserve.withdraw(wallet2.address, withdrawalAmount);

      const { timestamp } = await getBlock(withdrawalTx.transactionHash);
      const { timestamp: secondTimestamp } = await getBlock(secondWithdrawalTx.transactionHash);

      expect(withdrawalTx)
        .to.emit(prizeReserve, 'NewWithdrawalTwab')
        .withArgs([toWei('0'), timestamp]);

      expect(secondWithdrawalTx)
        .to.not.emit(prizeReserve, 'NewWithdrawalTwab')
        .withArgs([toWei('100'), secondTimestamp]);

      expect(withdrawalTx)
        .to.emit(prizeReserve, 'Withdrawn')
        .withArgs(contractsOwner.address, wallet2.address, withdrawalAmount);

      expect(secondWithdrawalTx)
        .to.emit(prizeReserve, 'Withdrawn')
        .withArgs(contractsOwner.address, wallet2.address, withdrawalAmount);
    });

    it('should fail to withdraw if caller is not the owners', async () => {
      await expect(prizeReserve.connect(wallet2).withdraw(wallet2.address, toWei('50'))).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should fail to withdraw if recipient is address zero', async () => {
      await expect(prizeReserve.withdraw(AddressZero, toWei('50'))).to.be.revertedWith(
        'ERC20: transfer to the zero address',
      );
    });

    it('should fail to withdraw if amount requested exceeds balance', async () => {
      await expect(prizeReserve.withdraw(wallet2.address, toWei('150'))).to.be.revertedWith(
        'ERC20: transfer amount exceeds balance',
      );
    });
  });
});
