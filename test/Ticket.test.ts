import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet } from 'ethers';
import { ethers, artifacts } from 'hardhat';

const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;

const increaseTime = async (time: number) => {
  await provider.send('evm_increaseTime', [time]);
  await provider.send('evm_mine', []);
};

function printBalances(balances: any) {
  balances = balances.filter((balance: any) => balance.timestamp != 0);
  balances.map((balance: any) => {
    console.log(`Balance @ ${balance.timestamp}: ${ethers.utils.formatEther(balance.balance)}`);
  });
}

describe('Ticket', () => {
  let ticket: Contract;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;

  beforeEach(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();

    const ticketFactory: ContractFactory = await ethers.getContractFactory('TicketHarness');
    ticket = await ticketFactory.deploy();

    await ticket.initialize('PoolTogether Dai Ticket', 'PcDAI', 18);
  });

  describe('transfer()', () => {
    it('should transfer tickets', async () => {
      const balanceBefore = toWei('100');

      await ticket.mint(wallet1.address, balanceBefore);
      await increaseTime(60);
      const latestBlockBefore = await provider.getBlock('latest');

      const transferBalance = toWei('50');
      await ticket.transfer(wallet2.address, transferBalance);

      expect(await ticket.getBalance(wallet1.address, latestBlockBefore.timestamp)).to.equal(
        balanceBefore,
      );

      const latestBlockAfter = await provider.getBlock('latest');

      expect(await ticket.getBalance(wallet1.address, latestBlockAfter.timestamp + 1)).to.equal(
        transferBalance,
      );
    });

    it.only('should correctly handle a full buffer', async () => {
      const cardinality = await ticket.CARDINALITY();
      const balanceBefore = toWei('1000');
      const blocks = [];

      await ticket.mint(wallet1.address, balanceBefore);

      for (let i = 0; i < cardinality; i++) {
        await ticket.transfer(wallet2.address, toWei('1'));
        blocks.push(await provider.getBlock('latest'));
      }

      // printBalances(await ticket.getBalances(wallet1.address));

      // Should have nothing at beginning of time
      expect(await ticket.getBalance(wallet1.address, 0)).to.equal('0');

      // Should have 1000 - cardinality at end of time
      let lastTime = blocks[blocks.length - 1].timestamp;

      expect(await ticket.getBalance(wallet1.address, lastTime)).to.equal(
        toWei('1000').sub(toWei('1').mul(cardinality)),
      );

      // Should match each and every balance change
      for (let i = 0; i < cardinality; i++) {
        let expectedBalance = toWei('1000').sub(toWei('1').mul(i + 1));
        let actualBalance = await ticket.getBalance(wallet1.address, blocks[i].timestamp);

        expect(actualBalance).to.equal(expectedBalance);
      }
    });
  });

  describe('claim', async () => {
    let claimable: any;

    beforeEach(async () => {
      let IClaimable = await artifacts.readArtifact('IClaimable');
      claimable = await deployMockContract(wallet1, IClaimable.abi);
    });

    it('should pass a zero balance', async () => {
      await claimable.mock.claim.withArgs(wallet1.address, [0], [0], '0x').returns(true);
      await ticket.claim(wallet1.address, claimable.address, [0], '0x');
    });

    it('should pass the actual balance', async () => {
      const mintAmount = toWei('1000');

      await ticket.mint(wallet1.address, mintAmount);

      await increaseTime(60);
      const block = await provider.getBlock('latest');

      await ticket.mint(wallet1.address, mintAmount);

      await claimable.mock.claim
        .withArgs(wallet1.address, [block.timestamp], [mintAmount], '0x')
        .returns(true);
      await ticket.claim(wallet1.address, claimable.address, [block.timestamp], '0x');
    });
  });
});
