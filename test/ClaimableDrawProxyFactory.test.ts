import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { getSigners } = ethers;
describe('ClaimableDrawProxyFactory', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let claimableDrawProxyFactory: Contract;

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    const ClaimableDrawProxyFactoryFactory: ContractFactory = await ethers.getContractFactory(
      'ClaimableDrawProxyFactory',
    );
    claimableDrawProxyFactory = await ClaimableDrawProxyFactoryFactory.deploy();
  });

  describe('create()', () => {
    it('should create a new claimable draw instance', async () => {
      await expect(await claimableDrawProxyFactory.create()).to.emit(
        claimableDrawProxyFactory,
        'ProxyCreated',
      );
    });
  });
});
