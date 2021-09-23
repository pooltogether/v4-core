import { expect } from 'chai';
import { ethers } from 'hardhat';
import { constants, Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
const { getSigners } = ethers;
const { parseEther: toWei } = ethers.utils;
describe('Reserve', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;
  let reserve: Contract;
  let ticket: Contract;

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    const ReserveHarnessFactory: ContractFactory = await ethers.getContractFactory(
      'ReserveHarness',
    );

    const erc20MintableFactory: ContractFactory = await ethers.getContractFactory(
      'ERC20Mintable',
    );
    ticket = await erc20MintableFactory.deploy('Dai Stablecoin', 'DAI');

    reserve = await ReserveHarnessFactory.deploy(wallet1.address, ticket.address);
  });

  describe('checkpoint()', () => {
    it('will succeed creating checkpoint with 0 balance', async () => {
      await expect(reserve.checkpoint())
        .to.not.emit(reserve, 'Checkpoint')
        .withArgs(0, 0)
    });

    it('will succeed creating checkpoint with positive balance', async () => {
      await ticket.mint(reserve.address, toWei('100'))
      await expect(reserve.checkpoint())
        .to.emit(reserve, 'Checkpoint')
        .withArgs(toWei('100'), 0)
    });

    it('will succeed creating checkpoint with positive balance and after withdrawal', async () => {
      await ticket.mint(reserve.address, toWei('100'))
      await reserve.withdrawTo(wallet2.address, toWei('100'))
      await ticket.mint(reserve.address, toWei('100'))
      await expect(reserve.checkpoint())
        .to.emit(reserve, 'Checkpoint')
        .withArgs(toWei('200'), toWei('100'))
    });

  })

  describe('withdrawTo()', () => {

  })

  describe('getReserveBetween()', () => {

  })

  describe('__getReserveAccumulatedAt()', () => {
    it('y', async () => {
      await expect(reserve.__getReserveAccumulatedAt()).to.be.revertedWith('DRB/future-draw')
    });

  })


})