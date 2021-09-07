import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { ethers, artifacts } from 'hardhat';
import { Artifact } from 'hardhat/types';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract, ContractFactory, constants } from 'ethers';

const { getSigners } = ethers;
const { AddressZero } = constants;
const debug = require('debug')('ptv4:PrizeSplitStrategy');
const toWei = (val: string | number) => ethers.utils.parseEther('' + val)

describe('PrizeSplitStrategy', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;
  let wallet4: SignerWithAddress;
  let prizeSplitStrategy: Contract;
  let ticket: Contract;
  let PrizePool: Artifact;
  let prizePool: MockContract;

  let prizeSplitStrategyFactory: ContractFactory
  let erc20MintableFactory: ContractFactory

  before(async () => {
    [wallet1, wallet2, wallet3, wallet4] = await getSigners();

    prizeSplitStrategyFactory = await ethers.getContractFactory(
      'PrizeSplitStrategy',
    );
    erc20MintableFactory = await ethers.getContractFactory(
      'ERC20Mintable',
    );
    PrizePool = await artifacts.readArtifact('PrizePool');
  });

  beforeEach(async () => {
    prizeSplitStrategy = await prizeSplitStrategyFactory.deploy();

    debug('mocking ticket and prizePool...');
    ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
    prizePool = await deployMockContract(wallet1 as Signer, PrizePool.abi);
    await prizePool.mock.tokens.returns([ticket.address, ticket.address])

    debug('initialize prizeSplitStrategy...');
    await prizeSplitStrategy.initialize(prizePool.address);
  });

  describe('distribute()', () => {
    it('should fail to capture award balance when prize split is unset', async () => {
      await expect(prizeSplitStrategy.distribute())
        .to.be.revertedWith('PrizeSplitStrategy/prize-split-unavailable')
    });

    it('should fail to capture award balance when prize split is below 100%', async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 500,
          token: 1,
        },
      ])
      await expect(prizeSplitStrategy.distribute())
        .to.be.revertedWith('PrizeSplitStrategy/invalid-prizesplit-percentage-total')
    });

    it('should award 100% of the captured balance to the PrizeReserve', async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 1000,
          token: 1,
        },
      ])
      await prizePool.mock.captureAwardBalance.returns(toWei('100'))
      await prizePool.mock.award.withArgs(wallet2.address, toWei('100'), ticket.address).returns()
      // Distribute Award
      const distribute = await prizeSplitStrategy.distribute()
      // Verify Contract Events
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'Distribute')
        .withArgs(toWei('100'))
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
        .withArgs(wallet2.address, toWei('100'), ticket.address)
    });

    it('should award (50%/50%) the captured balance to the PrizeReserve and a secondary account.', async () => {
      await prizeSplitStrategy.setPrizeSplits([
        {
          target: wallet2.address,
          percentage: 500,
          token: 1,
        },
        {
          target: wallet3.address,
          percentage: 500,
          token: 0,
        },
      ])
      await prizePool.mock.captureAwardBalance.returns(toWei('100'))
      // Mock PrizeReserve Award Sponsorhip
      await prizePool.mock.award.withArgs(wallet2.address, toWei('50'), ticket.address).returns()
      // Mock Secondary Wallet Award Sponsorhip
      await prizePool.mock.award.withArgs(wallet3.address, toWei('50'), ticket.address).returns()
      // Distribute Award
      const distribute = await prizeSplitStrategy.distribute()
      // Verify Contract Events
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'Distribute')
        .withArgs(toWei('100'))
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
        .withArgs(wallet2.address, toWei('50'), ticket.address)
      await expect(distribute)
        .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
        .withArgs(wallet3.address, toWei('50'), ticket.address)
    });

  })


})