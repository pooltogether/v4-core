import { BigNumber } from '@ethersproject/bignumber';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { utils, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

import { increaseTime as increaseTimeHelper } from '../helpers';

const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;

const increaseTime = (time: number) => increaseTimeHelper(provider, time);

type BinarySearchResult = {
  balance: BigNumber;
  timestamp: number;
};

const calculateBalance = (response: BinarySearchResult[]) => {
  const beforeOrAt = response[0];
  const atOrAfter = response[1];

  const beforeOrAtBalance = beforeOrAt.balance;
  const atOrAfterBalance = atOrAfter.balance;

  const differenceInBalance = ethers.utils.formatUnits(atOrAfterBalance.sub(beforeOrAtBalance));

  const beforeOrAtTimestamp = beforeOrAt.timestamp;
  const atOrAfterTimestamp = atOrAfter.timestamp;

  const differenceInTimestamp = atOrAfterTimestamp - beforeOrAtTimestamp;

  return Number(differenceInBalance) / differenceInTimestamp;
};

describe('Ticket', () => {
  let ticket: Contract;
  let cardinality: number;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;

  let isInitializeTest = false;

  const initializeTicket = async (decimals: number = 18) => {
    await ticket.initialize('PoolTogether Dai Ticket', 'PcDAI', decimals);
  };

  beforeEach(async () => {
    [wallet1, wallet2] = await getSigners();

    const ticketFactory: ContractFactory = await ethers.getContractFactory('TicketHarness');
    ticket = await ticketFactory.deploy();
    cardinality = await ticket.CARDINALITY();

    if (!isInitializeTest) {
      await initializeTicket();
    }
  });

  describe('initialize()', () => {
    before(() => {
      isInitializeTest = true;
    });

    after(() => {
      isInitializeTest = false;
    });

    it('should initialize ticket', async () => {
      await initializeTicket();

      expect(await ticket.name()).to.equal('PoolTogether Dai Ticket');
      expect(await ticket.symbol()).to.equal('PcDAI');
      expect(await ticket.decimals()).to.equal(18);
      expect(await ticket.owner()).to.equal(wallet1.address);
    });

    it('should set custom decimals', async () => {
      const ticketDecimals = 8;

      await initializeTicket(ticketDecimals);
      expect(await ticket.decimals()).to.equal(ticketDecimals);
    });

    it('should fail if token decimal is not greater than 0', async () => {
      await expect(initializeTicket(0)).to.be.revertedWith('Ticket/decimals-gt-zero');
    });
  });

  describe('decimals()', () => {
    it('should return default decimals', async () => {
      expect(await ticket.decimals()).to.equal(18);
    });
  });

  describe('balanceOf()', () => {
    it('should return user balance', async () => {
      const mintBalance = toWei('1000');

      await ticket.mint(wallet1.address, mintBalance);

      expect(await ticket.balanceOf(wallet1.address)).to.equal(mintBalance);
    });
  });

  describe('totalSupply()', () => {
    it('should return total supply of tickets', async () => {
      const mintBalance = toWei('1000');

      await ticket.mint(wallet1.address, mintBalance);
      await ticket.mint(wallet2.address, mintBalance);

      expect(await ticket.totalSupply()).to.equal(mintBalance.mul(2));
    });
  });

  describe('_moduloCardinality()', () => {
    it('should get correct twab index', async () => {
      for (let i = 0; i < cardinality * 2; i++) {
        if (i < cardinality) {
          expect(await ticket.moduloCardinality(i)).to.equal(i);
        } else {
          // We should go back to beginning of the circular buffer array
          expect(await ticket.moduloCardinality(i)).to.equal(i % cardinality);
        }
      }
    });
  });

  describe('_mostRecentTwabIndexOfUser()', () => {
    it('should return user default twab index if no transfer has happened', async () => {
      expect(await ticket.mostRecentTwabIndexOfUser(wallet1.address)).to.equal(cardinality - 1);
    });

    it('should return user most recent twab index if a transfer has happened', async () => {
      expect(await ticket.mostRecentTwabIndexOfUser(wallet1.address)).to.equal(cardinality - 1);

      await ticket.mint(wallet1.address, toWei('1000'));

      expect(await ticket.mostRecentTwabIndexOfUser(wallet1.address)).to.equal(0);

      await ticket.transfer(wallet2.address, toWei('100'));

      expect(await ticket.mostRecentTwabIndexOfUser(wallet2.address)).to.equal(0);
      expect(await ticket.mostRecentTwabIndexOfUser(wallet1.address)).to.equal(1);
    });
  });

  describe('_binarySearch()', () => {
    it('should perform a binary search', async () => {
      const mintAmount = toWei('1000');

      await ticket.mint(wallet1.address, mintAmount);
      const timestampAfterFirstMint = (await provider.getBlock('latest')).timestamp;

      await ticket.mint(wallet1.address, mintAmount);
      const timestampAfterSecondMint = (await provider.getBlock('latest')).timestamp;

      await ticket.mint(wallet1.address, mintAmount);

      await ticket
        .binarySearch(wallet1.address, timestampAfterFirstMint)
        .then((response: BinarySearchResult[]) =>
          expect(calculateBalance(response)).to.equal(1000),
        );

      await ticket
        .binarySearch(wallet1.address, timestampAfterSecondMint)
        .then((response: BinarySearchResult[]) =>
          expect(calculateBalance(response)).to.equal(2000),
        );
    });
  });

  describe('_newTwab()', () => {
    it('should record a new twab', async () => {
      const mostRecentTwabIndex = await ticket.mostRecentTwabIndexOfUser(wallet1.address);

      expect(await ticket.newTwab(wallet1.address, mostRecentTwabIndex))
        .to.emit(ticket, 'NewTwab')
        .withArgs(wallet1.address, [toWei('0'), (await provider.getBlock('latest')).timestamp]);
    });

    it('should return early if a twab already exists for this timestamp', async () => {
      const mostRecentTwabIndex = await ticket.mostRecentTwabIndexOfUser(wallet1.address);

      await ticket.newTwab(wallet1.address, mostRecentTwabIndex);

      await increaseTime(-1);

      const nextTwabIndex = mostRecentTwabIndex.add(1) % (await ticket.CARDINALITY());

      expect(await ticket.newTwab(wallet1.address, nextTwabIndex)).to.not.emit(ticket, 'NewTwab');
    });

    it('should fail to record a new twab if balance overflow', async () => {
      const balanceOverflow = BigNumber.from(1);
      const maxBalance = BigNumber.from(2).pow(223);

      for (let index = 0; index < 2; index++) {
        ticket.mint(wallet1.address, maxBalance);

        if (index === 1) {
          await expect(ticket.mint(wallet1.address, balanceOverflow)).to.be.revertedWith(
            "SafeCast: value doesn't fit in 224 bits",
          );
        }
      }
    });
  });

  describe('_transfer()', () => {
    const mintAmount = toWei('2500');
    const transferAmount = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(wallet1.address, mintAmount);
    });

    it('should transfer tickets from sender to recipient', async () => {
      expect(await ticket.transferTo(wallet1.address, wallet2.address, transferAmount))
        .to.emit(ticket, 'Transfer')
        .withArgs(wallet1.address, wallet2.address, transferAmount);

      expect(
        await ticket.getBalance(wallet2.address, (await provider.getBlock('latest')).timestamp),
      ).to.equal(transferAmount);

      expect(
        await ticket.getBalance(wallet1.address, (await provider.getBlock('latest')).timestamp),
      ).to.equal(mintAmount.sub(transferAmount));
    });

    it('should fail to transfer tickets if sender address is address zero', async () => {
      await expect(
        ticket.transferTo(ethers.constants.AddressZero, wallet2.address, transferAmount),
      ).to.be.revertedWith('ERC20: transfer from the zero address');
    });

    it('should fail to transfer tickets if receiver address is address zero', async () => {
      await expect(
        ticket.transferTo(wallet1.address, ethers.constants.AddressZero, transferAmount),
      ).to.be.revertedWith('ERC20: transfer to the zero address');
    });

    it('should fail to transfer tickets if transfer amount exceeds sender balance', async () => {
      const insufficientMintAmount = toWei('5000');

      await expect(
        ticket.transferTo(wallet1.address, wallet2.address, insufficientMintAmount),
      ).to.be.revertedWith('ERC20: transfer amount exceeds balance');
    });
  });

  describe('_mint()', () => {
    const mintAmount = toWei('1000');

    it('should mint tickets to user', async () => {
      expect(await ticket.mint(wallet1.address, mintAmount))
        .to.emit(ticket, 'Transfer')
        .withArgs(ethers.constants.AddressZero, wallet1.address, mintAmount);

      expect(
        await ticket.getBalance(wallet1.address, (await provider.getBlock('latest')).timestamp),
      ).to.equal(mintAmount);

      expect(await ticket.totalSupply()).to.equal(mintAmount);
    });

    it('should fail to mint tickets if user address is address zero', async () => {
      await expect(ticket.mint(ethers.constants.AddressZero, mintAmount)).to.be.revertedWith(
        'ERC20: mint to the zero address',
      );
    });
  });

  describe('_burn()', () => {
    const burnAmount = toWei('500');
    const mintAmount = toWei('1500');

    it('should burn tickets from user balance', async () => {
      await ticket.mint(wallet1.address, mintAmount);

      expect(await ticket.burn(wallet1.address, burnAmount))
        .to.emit(ticket, 'Transfer')
        .withArgs(wallet1.address, ethers.constants.AddressZero, burnAmount);

      expect(
        await ticket.getBalance(wallet1.address, (await provider.getBlock('latest')).timestamp),
      ).to.equal(mintAmount.sub(burnAmount));

      expect(await ticket.totalSupply()).to.equal(mintAmount.sub(burnAmount));
    });

    it('should fail to burn tickets from user balance if user address is address zero', async () => {
      await expect(ticket.burn(ethers.constants.AddressZero, mintAmount)).to.be.revertedWith(
        'ERC20: burn from the zero address',
      );
    });

    it('should fail to burn tickets from user balance if burn amount exceeds user balance', async () => {
      const insufficientMintAmount = toWei('250');

      await ticket.mint(wallet1.address, insufficientMintAmount);

      await expect(ticket.burn(wallet1.address, mintAmount)).to.be.revertedWith(
        'ERC20: burn amount exceeds balance',
      );
    });
  });

  describe('getBalance()', () => {
    const balanceBefore = toWei('1000');

    beforeEach(async () => {
      const timestampBeforeEach = (await provider.getBlock('latest')).timestamp;

      await ticket.mint(wallet1.address, balanceBefore);
    });

    it('should get correct balance after a ticket transfer', async () => {
      const transferAmount = toWei('500');

      await increaseTime(60);

      const timestampBefore = (await provider.getBlock('latest')).timestamp;

      await ticket.transfer(wallet2.address, transferAmount);

      expect(await ticket.getBalance(wallet1.address, timestampBefore)).to.equal(balanceBefore);

      const timestampAfter = (await provider.getBlock('latest')).timestamp;

      expect(await ticket.getBalance(wallet1.address, timestampAfter)).to.equal(
        balanceBefore.sub(transferAmount),
      );
    });

    it('should get correct balance while looping through a full buffer', async () => {
      const transferAmount = toWei('1');
      const blocks = [];

      for (let i = 0; i < cardinality; i++) {
        await ticket.transfer(wallet2.address, transferAmount);
        blocks.push(await provider.getBlock('latest'));
      }

      // Should have nothing at beginning of time
      expect(await ticket.getBalance(wallet1.address, 0)).to.equal('0');

      // Should have 1000 - cardinality at end of time
      const lastTime = blocks[blocks.length - 1].timestamp;

      expect(await ticket.getBalance(wallet1.address, lastTime)).to.equal(
        balanceBefore.sub(transferAmount.mul(cardinality)),
      );

      // Should match each and every balance change
      for (let i = 0; i < cardinality; i++) {
        const expectedBalance = balanceBefore.sub(transferAmount.mul(i + 1));
        const actualBalance = await ticket.getBalance(wallet1.address, blocks[i].timestamp);

        expect(actualBalance).to.equal(expectedBalance);
      }
    });
  });

  describe('getBalances()', () => {
    it('should get user balances', async () => {
      const mintAmount = toWei('2000');
      const transferAmount = toWei('500');
      const timestampBefore = (await provider.getBlock('latest')).timestamp;

      await ticket.mint(wallet1.address, mintAmount);
      await ticket.transfer(wallet2.address, transferAmount);

      const balances = await ticket.getBalances(wallet1.address, [
        timestampBefore,
        timestampBefore + 1,
        timestampBefore + 2,
      ]);

      expect(balances[0]).to.equal(toWei('0'));
      expect(balances[1]).to.equal(mintAmount);
      expect(balances[2]).to.equal(mintAmount.sub(transferAmount));
    });
  });
});
