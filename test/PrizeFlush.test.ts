import { expect } from 'chai';
import { ethers, artifacts } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';
import { Signer } from '@ethersproject/abstract-signer';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
const { getSigners } = ethers;
const { parseEther: toWei } = ethers.utils;

describe('PrizeFlush', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;
  let prizeFlush: Contract;
  let reserve: Contract;
  let ticket: Contract;
  let strategy: MockContract;
  let prizeFlushFactory: ContractFactory;
  let reserveFactory: ContractFactory;
  let erc20MintableFactory: ContractFactory;
  let prizeSplitStrategyFactory: ContractFactory;

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
    erc20MintableFactory = await ethers.getContractFactory('ERC20Mintable');
    prizeFlushFactory = await ethers.getContractFactory('PrizeFlush');
    reserveFactory = await ethers.getContractFactory('ReserveHarness');
    prizeSplitStrategyFactory = await ethers.getContractFactory('PrizeSplitStrategy');

    let PrizeSplitStrategy = await artifacts.readArtifact('PrizeSplitStrategy');
    strategy = await deployMockContract(wallet1 as Signer, PrizeSplitStrategy.abi);
  });

  beforeEach(async () => {
    ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
    reserve = await reserveFactory.deploy(wallet1.address, ticket.address);
    prizeFlush = await prizeFlushFactory.deploy(wallet1.address, ticket.address);

    await reserve.setManager(prizeFlush.address)
  });


  describe('flush()', () => {
    it('should flush prizes', async () => {
      await strategy.mock.distribute.returns(toWei('100'))
      await ticket.mint(reserve.address, toWei('100'))
      expect(prizeFlush.flush(
        strategy.address,
        reserve.address,
        wallet2.address,
        toWei('100')
      ))
        .to.emit(prizeFlush, 'Flushed')
        .withArgs(wallet2.address, toWei('100'))
    })
  })
})