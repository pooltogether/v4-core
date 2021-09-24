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

  // Contracts
  let prizeFlush: Contract;
  let reserve: Contract;
  let ticket: Contract;
  let strategy: MockContract;
  let prizeFlushFactory: ContractFactory;
  let reserveFactory: ContractFactory;
  let erc20MintableFactory: ContractFactory;
  let prizeSplitStrategyFactory: ContractFactory;

  let DESTINATION: any;

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
    DESTINATION = wallet3.address
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
    prizeFlush = await prizeFlushFactory.deploy(
      wallet1.address,
      DESTINATION,
      strategy.address,
      reserve.address
    );
    await reserve.setManager(prizeFlush.address)
  });


  describe('flush()', () => {
    it('should fail to withdrawTo if negative balance on reserve', async () => {
      await strategy.mock.distribute.returns(toWei('0'))
      await expect(prizeFlush.flush())
        .to.not.emit(prizeFlush, 'Flushed')
    })

    it('should flush prizes if positive balance on reserve.', async () => {
      await strategy.mock.distribute.returns(toWei('100'))
      await ticket.mint(reserve.address, toWei('100'))
      await expect(prizeFlush.flush())
        .to.emit(prizeFlush, 'Flushed')
        .and.to.emit(reserve, 'Withdrawn')
    })
  })
})