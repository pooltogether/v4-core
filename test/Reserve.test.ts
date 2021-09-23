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
    it('two checkpoints in a row, no event from second', async () => {
      await ticket.mint(reserve.address, toWei('100'))
      await reserve.checkpoint()

      await expect(reserve.checkpoint())
        .to.not.emit(reserve, 'Checkpoint')
    });

    it('two checkpoints same block', async () => {
      await ticket.mint(reserve.address, toWei('100'))
      await expect(reserve.doubleCheckpoint(ticket.address, toWei("50")))
        .to.emit(reserve, 'Checkpoint').withArgs(toWei('100'), 0).
        and.to.emit(reserve, 'Checkpoint').withArgs(toWei('150'), 0)

      expect(await reserve.getCardinality()).to.eq(1)
    });

  })

  describe('withdrawTo()', () => {

  })

  describe('getReserveAccumulatedBetween()', () => {
      
    it('start and end before observations', async() => {
      // s e [] 
      const observations = [
        {
          timestamp: 5,
          amount: 70
        },
        {
          timestamp: 8,
          amount: 72
        }
      ]
      await reserve.setObservationsAt(observations)
      const result = await reserve.getReserveAccumulatedBetween(2, 3)
      expect(result).to.equal(0)
    })

    it('start before and end inside', async() => {
            // s [ e ]
      const observations = [
        {
          timestamp: 5,
          amount: 70
        },
        {
          timestamp: 8,
          amount: 72
        }
      ]
      await reserve.setObservationsAt(observations)
      const result = await reserve.getReserveAccumulatedBetween(2, 6)
      expect(result).to.equal(70)
    })

    it('start before and end inside', async() => {
      // s [e ]
      const observations = [{
          timestamp: 5,
          amount: 70
        },
        {
          timestamp: 8,
          amount: 72
        }]
      await reserve.setObservationsAt(observations)
      const result = await reserve.getReserveAccumulatedBetween(2, 5)
      expect(result).to.equal(70)
      })

      it('start before and end inside', async() => {
        // s [ e]
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(2, 8)
        expect(result).to.equal(72)
      })

      it('start before and end inside', async() => {
        // s [ e]
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(2, 8)
        expect(result).to.equal(72)
      })
           
      it('start before and end inside', async() => {
        // [ s e ]
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(6, 7)
        expect(result).to.equal(0)
      })

      it('start before and end inside', async() => {
        // [ s e]
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(6, 8)
        expect(result).to.equal(2)
      })


      it('start before and end inside', async() => {
        // [s e]
        

        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(5, 8)
        expect(result).to.equal(2) 
        // todo: think about this behaviour -- should it be 72?

      })

      it('start before and end inside', async() => {
        // [ s ] e
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(6, 10)
        expect(result).to.equal(2)
      })

      it('start before and end inside', async() => {
        // [ s] e
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(8, 29)
        expect(result).to.equal(0)
      })

      it('start before and end inside', async() => {
        // [] s e 
        const observations = [{timestamp: 5,amount: 70},{timestamp: 8,amount: 72}]

        await reserve.setObservationsAt(observations)
        const result = await reserve.getReserveAccumulatedBetween(18, 29)
        expect(result).to.equal(0)
      })

  })
})