import { Signer } from '@ethersproject/abstract-signer';
import { BigNumber } from '@ethersproject/bignumber';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { utils, Contract, ContractFactory } from 'ethers';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import hre, { ethers } from 'hardhat';

import { increaseTime as increaseTimeHelper } from './helpers/increaseTime';

const { constants, getSigners, provider } = ethers;
const { AddressZero } = constants;
const { getBlock } = provider;
const { parseEther: toWei } = utils;

const increaseTime = (time: number) => increaseTimeHelper(provider, time);

type BinarySearchResult = {
  amount: BigNumber;
  timestamp: number;
};

const calculateTwab = (response: BinarySearchResult[]) => {
  const beforeOrAt = response[0];
  const atOrAfter = response[1];

  const beforeOrAtAmount = beforeOrAt.amount;
  const atOrAfterAmount = atOrAfter.amount;

  const differenceInAmount = ethers.utils.formatUnits(atOrAfterAmount.sub(beforeOrAtAmount));

  const beforeOrAtTimestamp = beforeOrAt.timestamp;
  const atOrAfterTimestamp = atOrAfter.timestamp;

  const differenceInTimestamp = atOrAfterTimestamp - beforeOrAtTimestamp;

  return Number(differenceInAmount) / differenceInTimestamp;
};

describe('Ticket', () => {
  let cardinality: number;
  let controller: MockContract;
  let ticket: Contract;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;

  let isInitializeTest = false;

  const ticketName = 'PoolTogether Dai Ticket';
  const ticketSymbol = 'PcDAI';
  const ticketDecimals = 18;

  const initializeTicket = async (
    decimals: number = ticketDecimals,
    controllerAddress: string = controller.address,
  ) => {
    await ticket.initialize(ticketName, ticketSymbol, decimals, controllerAddress);
  };

  beforeEach(async () => {
    [wallet1, wallet2] = await getSigners();

    const TokenControllerInterface = await hre.artifacts.readArtifact('contracts/import/token/TokenControllerInterface.sol:TokenControllerInterface');
    controller = await deployMockContract(wallet1 as Signer, TokenControllerInterface.abi);

    await controller.mock.beforeTokenTransfer.returns();

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

      expect(await ticket.name()).to.equal(ticketName);
      expect(await ticket.symbol()).to.equal(ticketSymbol);
      expect(await ticket.decimals()).to.equal(ticketDecimals);
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

    it('should fail if controller address is address 0', async () => {
      await expect(initializeTicket(ticketDecimals, AddressZero)).to.be.revertedWith(
        'Ticket/controller-not-zero-address',
      );
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

  describe('_mostRecentTwabIndexOfTotalSupply()', () => {
    it('should return default total supply twab index if no mint has happened', async () => {
      expect(await ticket.mostRecentTwabIndexOfTotalSupply()).to.equal(cardinality - 1);
    });

    it('should return total supply most recent twab index if a transfer has happened', async () => {
      expect(await ticket.mostRecentTwabIndexOfTotalSupply()).to.equal(cardinality - 1);

      await ticket.mint(wallet1.address, toWei('1000'));

      expect(await ticket.mostRecentTwabIndexOfTotalSupply()).to.equal(0);

      await ticket.mint(wallet2.address, toWei('100'));

      expect(await ticket.mostRecentTwabIndexOfTotalSupply()).to.equal(1);
    });
  });

  describe('_binarySearch()', () => {
    it('should perform a binary search', async () => {
      const mintAmount = toWei('1000');

      await ticket.mint(wallet1.address, mintAmount);
      const timestampAfterFirstMint = (await getBlock('latest')).timestamp;

      await ticket.mint(wallet1.address, mintAmount);
      const timestampAfterSecondMint = (await getBlock('latest')).timestamp;

      await ticket.mint(wallet1.address, mintAmount);
      const timestampAfterThirdMint = (await getBlock('latest')).timestamp;

      const userTwabs = [
        {
          amount: 0,
          timestamp: timestampAfterFirstMint,
        },
        {
          amount: mintAmount,
          timestamp: timestampAfterSecondMint,
        },
        {
          amount: mintAmount.mul(3),
          timestamp: timestampAfterThirdMint,
        },
      ];

      for (let index = 0; index < 29; index++) {
        userTwabs.push({
          amount: 0,
          timestamp: 0,
        });
      }

      const userTwabIndex = ticket.mostRecentTwabIndexOfUser(wallet1.address);

      await ticket
        .binarySearch(userTwabs, userTwabIndex, timestampAfterFirstMint)
        .then((response: BinarySearchResult[]) => expect(calculateTwab(response)).to.equal(1000));

      await ticket
        .binarySearch(userTwabs, userTwabIndex, timestampAfterSecondMint)
        .then((response: BinarySearchResult[]) => expect(calculateTwab(response)).to.equal(2000));
    });
  });

  describe('_newUserTwab()', () => {
    it('should record a new twab for user', async () => {
      const mostRecentTwabIndex = await ticket.mostRecentTwabIndexOfUser(wallet1.address);

      expect(await ticket.newUserTwab(wallet1.address, mostRecentTwabIndex))
        .to.emit(ticket, 'NewUserTwab')
        .withArgs(wallet1.address, [toWei('0'), (await getBlock('latest')).timestamp]);
    });

    it('should return early if a twab already exists for this timestamp', async () => {
      const mostRecentTwabIndex = await ticket.mostRecentTwabIndexOfUser(wallet1.address);

      await ticket.newUserTwab(wallet1.address, mostRecentTwabIndex);

      await increaseTime(-1);

      const nextTwabIndex = mostRecentTwabIndex.add(1) % (await ticket.CARDINALITY());

      expect(await ticket.newUserTwab(wallet1.address, nextTwabIndex)).to.not.emit(
        ticket,
        'NewUserTwab',
      );
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

  describe('_newTotalSupplyTwab()', () => {
    it('should record a new twab', async () => {
      const mostRecentTwabIndex = await ticket.mostRecentTwabIndexOfTotalSupply();

      expect(await ticket.newTotalSupplyTwab(mostRecentTwabIndex))
        .to.emit(ticket, 'NewTotalSupplyTwab')
        .withArgs([toWei('0'), (await getBlock('latest')).timestamp]);
    });

    it('should return early if a twab already exists for this timestamp', async () => {
      const mostRecentTwabIndex = await ticket.mostRecentTwabIndexOfUser(wallet1.address);

      await ticket.newTotalSupplyTwab(mostRecentTwabIndex);

      await increaseTime(-1);

      const nextTwabIndex = mostRecentTwabIndex.add(1) % (await ticket.CARDINALITY());

      expect(await ticket.newTotalSupplyTwab(nextTwabIndex)).to.not.emit(
        ticket,
        'NewTotalSupplyTwab',
      );
    });

    it('should fail to record a new twab if balance overflow', async () => {
      const balanceOverflow = BigNumber.from(1);
      const maxBalance = BigNumber.from(2).pow(223);

      for (let index = 0; index < 2; index++) {
        ticket.mint(wallet1.address, maxBalance);

        if (index === 1) {
          await expect(ticket.mint(wallet2.address, balanceOverflow)).to.be.revertedWith(
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
        await ticket.getBalance(wallet2.address, (await getBlock('latest')).timestamp),
      ).to.equal(transferAmount);

      expect(
        await ticket.getBalance(wallet1.address, (await getBlock('latest')).timestamp),
      ).to.equal(mintAmount.sub(transferAmount));
    });

    it('should fail to transfer tickets if sender address is address zero', async () => {
      await expect(
        ticket.transferTo(AddressZero, wallet2.address, transferAmount),
      ).to.be.revertedWith('ERC20: transfer from the zero address');
    });

    it('should fail to transfer tickets if receiver address is address zero', async () => {
      await expect(
        ticket.transferTo(wallet1.address, AddressZero, transferAmount),
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
        .withArgs(AddressZero, wallet1.address, mintAmount);

      expect(
        await ticket.getBalance(wallet1.address, (await getBlock('latest')).timestamp),
      ).to.equal(mintAmount);

      expect(await ticket.totalSupply()).to.equal(mintAmount);
    });

    it('should fail to mint tickets if user address is address zero', async () => {
      await expect(ticket.mint(AddressZero, mintAmount)).to.be.revertedWith(
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
        .withArgs(wallet1.address, AddressZero, burnAmount);

      expect(
        await ticket.getBalance(wallet1.address, (await getBlock('latest')).timestamp),
      ).to.equal(mintAmount.sub(burnAmount));

      expect(await ticket.totalSupply()).to.equal(mintAmount.sub(burnAmount));
    });

    it('should fail to burn tickets from user balance if user address is address zero', async () => {
      await expect(ticket.burn(AddressZero, mintAmount)).to.be.revertedWith(
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

  describe('getAverageBalance()', () => {
    const balanceBefore = toWei('1000');
    let timestamp: number

    beforeEach(async () => {
      await ticket.mint(wallet1.address, balanceBefore);
      timestamp = (await getBlock('latest')).timestamp;
      // console.log(`Minted at time ${timestamp}`)

    });

    it('should return an average of zero for pre-history requests', async () => {
      // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
      expect(await ticket.getAverageBalance(wallet1.address, timestamp - 100, timestamp - 50)).to.equal(toWei('0'));
    });

    it('should not project into the future', async () => {
      // at this time the user has held 1000 tokens for zero seconds
      // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
      expect(await ticket.getAverageBalance(wallet1.address, timestamp - 50, timestamp + 50)).to.equal(toWei('0'))
    })

    it('should return half the minted balance when the duration is centered over first twab', async () => {
      await increaseTime(100);
      // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
      expect(await ticket.getAverageBalance(wallet1.address, timestamp - 50, timestamp + 50)).to.equal(toWei('500'))
    })

    it('should return an accurate average when the range is after the last twab', async () => {
      await increaseTime(100);
      // console.log(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 51}`)
      expect(await ticket.getAverageBalance(wallet1.address, timestamp + 50, timestamp + 51)).to.equal(toWei('1000'))
    })
    
    context('with two twabs', () => {
      const transferAmount = toWei('500');
      let timestamp2: number

      beforeEach(async () => {
        // they've held 1000 for t+100 seconds
        await increaseTime(100);

        // now transfer out 500
        await ticket.transfer(wallet2.address, transferAmount);
        timestamp2 = (await getBlock('latest')).timestamp;
        // console.log(`Transferred at time ${timestamp2}`)

        // they've held 500 for t+100+100 seconds
        await increaseTime(100);
      })

      it('should return an average of zero for pre-history requests', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
        expect(await ticket.getAverageBalance(wallet1.address, timestamp - 100, timestamp - 50)).to.equal(toWei('0'));
      });

      it('should return half the minted balance when the duration is centered over first twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
        expect(await ticket.getAverageBalance(wallet1.address, timestamp - 50, timestamp + 50)).to.equal(toWei('500'))
      })

      it('should return an accurate average when the range is between twabs', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 55}`)
        expect(await ticket.getAverageBalance(wallet1.address, timestamp + 50, timestamp + 55)).to.equal(toWei('1000'))
      })

      it('should return an accurate average when the end is after the last twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp2 - 50}, ${timestamp2 + 50}`)
        expect(await ticket.getAverageBalance(wallet1.address, timestamp2 - 50, timestamp2 + 50)).to.equal(toWei('750'))
      })

      it('should return an accurate average when the range is after twabs', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp2 + 50}, ${timestamp2 + 51}`)
        expect(await ticket.getAverageBalance(wallet1.address, timestamp2 + 50, timestamp2 + 51)).to.equal(toWei('500'))
      })
    })

  })

  describe('getBalance()', () => {
    const balanceBefore = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(wallet1.address, balanceBefore);
    });

    it('should get correct balance after a ticket transfer', async () => {
      const transferAmount = toWei('500');

      await increaseTime(60);

      const timestampBefore = (await getBlock('latest')).timestamp;

      await ticket.transfer(wallet2.address, transferAmount);

      expect(await ticket.getBalance(wallet1.address, timestampBefore)).to.equal(balanceBefore);

      const timestampAfter = (await getBlock('latest')).timestamp;

      expect(await ticket.getBalance(wallet1.address, timestampAfter)).to.equal(
        balanceBefore.sub(transferAmount),
      );
    });

    it('should get correct balance while looping through a full buffer', async () => {
      const transferAmount = toWei('1');
      const blocks = [];

      for (let i = 0; i < cardinality; i++) {
        await ticket.transfer(wallet2.address, transferAmount);
        blocks.push(await getBlock('latest'));
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
      const timestampBefore = (await getBlock('latest')).timestamp;

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

  describe('getTotalSupply()', () => {
    const balanceBefore = toWei('1000');

    it('should get correct total supply after a transfer and burn', async () => {
      await ticket.mint(wallet1.address, balanceBefore);

      const transferAmount = toWei('500');
      const burnAmount = transferAmount;

      await increaseTime(60);

      const timestampBefore = (await getBlock('latest')).timestamp;

      await ticket.transfer(wallet2.address, transferAmount);

      expect(await ticket.getTotalSupply(timestampBefore)).to.equal(balanceBefore);

      const timestampAfterTransfer = (await getBlock('latest')).timestamp;

      expect(await ticket.getTotalSupply(timestampAfterTransfer)).to.equal(balanceBefore);

      await ticket.burn(wallet2.address, burnAmount);

      const timestampAfterBurn = (await getBlock('latest')).timestamp;

      expect(await ticket.getTotalSupply(timestampAfterBurn)).to.equal(
        balanceBefore.sub(burnAmount),
      );
    });

    it('should get correct total supply while looping through a full buffer', async () => {
      const burnAmount = toWei('1');
      const blocks = [];

      // Should have 0 at beginning of time
      const timestampBefore = (await getBlock('latest')).timestamp;

      expect(await ticket.getTotalSupply(timestampBefore)).to.equal(toWei('0'));

      await ticket.mint(wallet1.address, balanceBefore);

      const timestampAfterMint = (await getBlock('latest')).timestamp;

      // Should have 1000 after mint
      expect(await ticket.getTotalSupply(timestampAfterMint)).to.equal(balanceBefore);

      for (let i = 0; i < cardinality; i++) {
        await ticket.burn(wallet1.address, burnAmount);
        blocks.push(await getBlock('latest'));
      }

      // Should have 1000 - (1 * cardinality) at end of time
      const lastTime = blocks[blocks.length - 1].timestamp;

      expect(await ticket.getTotalSupply(lastTime)).to.equal(
        balanceBefore.sub(burnAmount.mul(cardinality)),
      );

      // Should match each and every total supply change
      for (let i = 0; i < cardinality; i++) {
        const expectedTotalSupply = balanceBefore.sub(burnAmount.mul(i + 1));
        const actualTotalSupply = await ticket.getTotalSupply(blocks[i].timestamp);

        expect(actualTotalSupply).to.equal(expectedTotalSupply);
      }
    });

    describe('getTotalSupplies()', () => {
      it('should get ticket total supplies', async () => {
        const mintAmount = toWei('2000');
        const burnAmount = toWei('500');
        const timestampBefore = (await getBlock('latest')).timestamp;

        await ticket.mint(wallet1.address, mintAmount);
        await ticket.burn(wallet1.address, burnAmount);

        const totalSupplies = await ticket.getTotalSupplies([
          timestampBefore,
          timestampBefore + 1,
          timestampBefore + 2,
        ]);

        expect(totalSupplies[0]).to.equal(toWei('0'));
        expect(totalSupplies[1]).to.equal(mintAmount);
        expect(totalSupplies[2]).to.equal(mintAmount.sub(burnAmount));
      });
    });
  });
});
