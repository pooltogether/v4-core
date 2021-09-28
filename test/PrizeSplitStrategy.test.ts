import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { ethers, artifacts } from 'hardhat';
import { Artifact } from 'hardhat/types';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract, ContractFactory } from 'ethers';

const { getSigners } = ethers;
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
    debug('mocking ticket and prizePool...');
    ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
    prizePool = await deployMockContract(wallet1 as Signer, PrizePool.abi);
    await prizePool.mock.ticket.returns(ticket.address);
    debug('deploy prizeSplitStrategy...');
    prizeSplitStrategy = await prizeSplitStrategyFactory.deploy(wallet1.address, prizePool.address);
  });

  /*============================================ */
  // Core Functions ----------------------------
  /*============================================ */
  describe('Core Functions', () => {
    describe('distribute()', () => {
      it('should stop executing if captured interest is 0', async () => {
        await prizePool.mock.captureAwardBalance.returns(toWei('0'))
        await prizePool.mock.award.withArgs(wallet2.address, toWei('0')).returns()
        const distribute = await prizeSplitStrategy.distribute()
        await expect(distribute)
          .to.not.emit(prizeSplitStrategy, 'Distributed')
          .withArgs(toWei('100'))
      })
      it('should award 100% of the captured balance to the PrizeReserve', async () => {
        await prizeSplitStrategy.setPrizeSplits([
          {
            target: wallet2.address,
            percentage: 1000
          },
        ])

        await prizePool.mock.captureAwardBalance.returns(toWei('100'))
        await prizePool.mock.award.withArgs(wallet2.address, toWei('100')).returns()
        const distribute = await prizeSplitStrategy.distribute()
        await expect(distribute)
          .to.emit(prizeSplitStrategy, 'Distributed')
          .withArgs(toWei('100'))
        await expect(distribute)
          .to.emit(prizeSplitStrategy, 'PrizeSplitAwarded')
          .withArgs(wallet2.address, toWei('100'), ticket.address)
      });
    })
  })

  /*============================================ */
  // Getter Functions --------------------------
  /*============================================ */
  describe('Getter Functions', () => {
    it('should ', async () => {

    });
  })
  /*============================================ */
  // Setter Functions --------------------------
  /*============================================ */
  describe('Setter Functions', () => {

  })

  /*============================================ */
  // Internal Functions ----------------------------
  /*============================================ */
  describe('Internal Functions', () => {

  })
  /*============================================ */
  // Core Functions ----------------------------
  /*============================================ */
  describe('core()', () => {

  })
})
