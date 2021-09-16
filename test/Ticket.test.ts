import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, BigNumber } from 'ethers';
import hre, { ethers } from 'hardhat';
import { start } from 'node:repl';

import { increaseTime as increaseTimeHelper } from './helpers/increaseTime';

const newDebug = require('debug')

const debug = newDebug("pt:Ticket.test.ts")

const { constants, getSigners, provider } = ethers;
const { AddressZero, MaxUint256 } = constants;
const { getBlock } = provider;
const { parseEther: toWei } = utils;

const increaseTime = (time: number) => increaseTimeHelper(provider, time);

async function deployTicketContract(ticketName: string, ticketSymbol: string, decimals: number, controllerAddress: string) {
  const ticketFactory: ContractFactory = await ethers.getContractFactory('TicketHarness');
  const ticketContract = await ticketFactory.deploy(ticketName, ticketSymbol, decimals, controllerAddress);
  return ticketContract;
}

async function printTwabs(ticketContract: Contract, wallet: SignerWithAddress, debugLog: any = debug) {
  const context = await ticketContract.getAccountDetails(wallet.address)
  debugLog(`Twab Context for ${wallet.address}: { balance: ${ethers.utils.formatEther(context.balance)}, nextTwabIndex: ${context.nextTwabIndex}, cardinality: ${context.cardinality}}`)
  const twabs = []
  for (var i = 0; i < context.cardinality; i++) {
    twabs.push(await ticketContract.getTwab(wallet.address, i));
  }
  twabs.forEach((twab, index) => {
    debugLog(`Twab ${index} { amount: ${twab.amount}, timestamp: ${twab.timestamp}}`)
  })
}

describe('Ticket', () => {
  let prizePool: MockContract;
  let ticket: Contract;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let wallet3: SignerWithAddress;

  const ticketName = 'PoolTogether Dai Ticket';
  const ticketSymbol = 'PcDAI';
  const ticketDecimals = 18;

  beforeEach(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();

    const PrizePool = await hre.artifacts.readArtifact(
      'contracts/prize-pool/PrizePool.sol:PrizePool',
    );

    prizePool = await deployMockContract(wallet1 as Signer, PrizePool.abi);
    ticket = await deployTicketContract(ticketName, ticketSymbol, ticketDecimals, prizePool.address);
    prizePool.mock.balanceCap.withArgs(ticket.address).returns(MaxUint256);
  });

  describe('constructor()', () => {
    it('should initialize ticket', async () => {
      let ticket = await deployTicketContract(ticketName, ticketSymbol, ticketDecimals, prizePool.address);

      expect(await ticket.name()).to.equal(ticketName);
      expect(await ticket.symbol()).to.equal(ticketSymbol);
      expect(await ticket.decimals()).to.equal(ticketDecimals);
    });

    it('should fail if token decimal is not greater than 0', async () => {
      await expect(deployTicketContract(ticketName, ticketSymbol, 0, prizePool.address)).to.be.revertedWith('ControlledToken/decimals-gt-zero');
    });

    it('should fail if controller address is address 0', async () => {
      await expect(deployTicketContract(ticketName, ticketSymbol, ticketDecimals, constants.AddressZero)).to.be.revertedWith(
        'ControlledToken/controller-not-zero-address',
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

  describe('flash loan attack', () => {
    let flashTimestamp: number
    let mintTimestamp: number

    beforeEach(async () => {
      await ticket.flashLoan(wallet1.address, toWei('100000'))
      flashTimestamp = (await provider.getBlock('latest')).timestamp
      await increaseTime(10)

      await ticket.mint(wallet1.address, toWei('100'))
      mintTimestamp = (await provider.getBlock('latest')).timestamp

      await increaseTime(20)
    })

    it('should not affect getBalanceAt()', async () => {
      expect(await ticket.getBalanceAt(wallet1.address, flashTimestamp - 1)).to.equal(0)
      expect(await ticket.getBalanceAt(wallet1.address, flashTimestamp)).to.equal(0)
      expect(await ticket.getBalanceAt(wallet1.address, flashTimestamp + 1)).to.equal(0)
    })

    it('should not affect getAverageBalanceBetween() for that time', async () => {
      expect(await ticket.getAverageBalanceBetween(wallet1.address, flashTimestamp - 1, flashTimestamp + 1)).to.equal(0)
    })

    it('should not affect subsequent twabs for getAverageBalanceBetween()', async () => {
      expect(await ticket.getAverageBalanceBetween(wallet1.address, mintTimestamp - 11, mintTimestamp + 11)).to.equal(toWei('50'))
    })
  })

  describe('twab lifetime', () => {
    let twabLifetime: number
    const mintBalance = toWei('1000')

    beforeEach(async () => {
      twabLifetime = await ticket.TWAB_TIME_TO_LIVE()
    })

    it('should expire old twabs and save gas', async () => {
      let quarterOfLifetime = twabLifetime / 4

      await ticket.mint(wallet1.address, mintBalance)

      // now try transfers
      for (var i = 0; i < 8; i++) {
        await increaseTime(quarterOfLifetime)
        await ticket.mint(wallet2.address, mintBalance)
        await ticket.transfer(wallet2.address, toWei('100'))
        await ticket.burn(wallet2.address, mintBalance.div(2))
      }

      await ticket.burn(wallet1.address, await ticket.balanceOf(wallet1.address))
      await ticket.burn(wallet2.address, await ticket.balanceOf(wallet2.address))

      // here we should have looped around.
    })
  })

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

      await increaseTime(10)

      expect(
        await ticket.getBalanceAt(wallet2.address, (await getBlock('latest')).timestamp),
      ).to.equal(transferAmount);

      expect(
        await ticket.getBalanceAt(wallet1.address, (await getBlock('latest')).timestamp),
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
    const debug = newDebug('pt:Ticket.test.ts:_mint()')
    const mintAmount = toWei('1000');

    it('should mint tickets to user', async () => {
      expect(await ticket.mint(wallet1.address, mintAmount))
        .to.emit(ticket, 'Transfer')
        .withArgs(AddressZero, wallet1.address, mintAmount);

      await increaseTime(10)

      expect(
        await ticket.getBalanceAt(wallet1.address, (await getBlock('latest')).timestamp),
      ).to.equal(mintAmount);

      expect(await ticket.totalSupply()).to.equal(mintAmount);
    });

    it('should fail to mint tickets if user address is address zero', async () => {
      await expect(ticket.mint(AddressZero, mintAmount)).to.be.revertedWith(
        'ERC20: mint to the zero address',
      );
    });

    it('should not record additional twabs when minting twice in the same block', async () => {
      expect(await ticket.mintTwice(wallet1.address, mintAmount))
        .to.emit(ticket, 'Transfer')
        .withArgs(AddressZero, wallet1.address, mintAmount);

      await printTwabs(ticket, wallet1, debug)

      const context = await ticket.getAccountDetails(wallet1.address)

      debug(`Twab Context: `, context)

      expect(context.cardinality).to.equal(2)
      expect(context.nextTwabIndex).to.equal(1)
      expect(await ticket.totalSupply()).to.equal(mintAmount.mul(2));
    })
  });

  describe('_burn()', () => {
    const debug = newDebug('pt:Ticket.test.ts:_burn()')

    const burnAmount = toWei('500');
    const mintAmount = toWei('1500');

    it('should burn tickets from user balance', async () => {
      await ticket.mint(wallet1.address, mintAmount);

      expect(await ticket.burn(wallet1.address, burnAmount))
        .to.emit(ticket, 'Transfer')
        .withArgs(wallet1.address, AddressZero, burnAmount);

      await increaseTime(1)

      expect(
        await ticket.getBalanceAt(wallet1.address, (await getBlock('latest')).timestamp),
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
  
  describe('getAverageTotalSupplyBetween()', () => {

    const balanceBefore = toWei('1000');
    let timestamp: number

    beforeEach(async () => {
      await ticket.mint(wallet1.address, balanceBefore);
      timestamp = (await getBlock('latest')).timestamp;
      debug(`minted ${ethers.utils.formatEther(balanceBefore)} @ timestamp ${timestamp}`)
      // console.log(`Minted at time ${timestamp}`)
    });

    it('should revert on unequal lenght inputs', async () => {
      const drawStartTimestamp = timestamp
      const drawEndTimestamp = timestamp
      await expect(ticket.getAverageBalancesBetween(wallet1.address, [drawStartTimestamp, drawStartTimestamp], [drawEndTimestamp])).
      to.be.revertedWith("Ticket/start-end-times-length-match")
    })

    it('should return an average of zero for pre-history requests', async () => {
       // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
      const drawStartTimestamp = timestamp - 100
      const drawEndTimestamp = timestamp - 50
      const result = await ticket.getAverageTotalSuppliesBetween([drawStartTimestamp], [drawEndTimestamp])
      result.forEach((res: any) => {
        expect(res).to.deep.equal(toWei('0'))
      });
    });

    it('should not project into the future', async () => {
      // at this time the user has held 1000 tokens for zero seconds
      // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
      const drawStartTimestamp = timestamp - 50
      const drawEndTimestamp = timestamp + 50
      const result = await ticket.getAverageTotalSuppliesBetween([drawStartTimestamp], [drawEndTimestamp])
      result.forEach((res: any) => {
        expect(res).to.deep.equal(toWei('0'))
      });
    })

    it('should return half the minted balance when the duration is centered over first twab', async () => {
      await increaseTime(100);
      // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
      const drawStartTimestamp = timestamp - 50
      const drawEndTimestamp = timestamp + 50
      const result = await ticket.getAverageTotalSuppliesBetween([drawStartTimestamp], [drawEndTimestamp])
      result.forEach((res: any) => {
        expect(res).to.deep.equal(toWei('500'))
      });
    })

    it('should return an accurate average when the range is after the last twab', async () => {
      await increaseTime(100);
      // console.log(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 51}`)
      const drawStartTimestamp = timestamp + 50
      const drawEndTimestamp = timestamp + 51
      const result = await ticket.getAverageTotalSuppliesBetween([drawStartTimestamp], [drawEndTimestamp])
      result.forEach((res: any) => {
        expect(res).to.deep.equal(toWei('1000'))
      });
    })
  });

  describe('getAverageBalanceBetween()', () => {
    const debug = newDebug('pt:Ticket.test.ts:getAverageBalanceBetween()')
    const balanceBefore = toWei('1000');
    let timestamp: number

    beforeEach(async () => {
      await ticket.mint(wallet1.address, balanceBefore);
      timestamp = (await getBlock('latest')).timestamp;
      debug(`minted ${ethers.utils.formatEther(balanceBefore)} @ timestamp ${timestamp}`)
    });

    it('should return an average of zero for pre-history requests', async () => {
      await printTwabs(ticket, wallet1, debug)
      expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp - 100, timestamp - 50)).to.equal(toWei('0'));
    });

    it('should not project into the future', async () => {
      // at this time the user has held 1000 tokens for zero seconds
      expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp - 50, timestamp + 50)).to.equal(toWei('0'))
    })

    it('should return half the minted balance when the duration is centered over first twab', async () => {
      await increaseTime(100);
      expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp - 50, timestamp + 50)).to.equal(toWei('500'))
    })

    it('should return an accurate average when the range is after the last twab', async () => {
      await increaseTime(100);
      expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp + 50, timestamp + 51)).to.equal(toWei('1000'))
    })

    context('with two twabs', () => {
      const transferAmount = toWei('500');
      let timestamp2: number

      beforeEach(async () => {
        // they've held 1000 for t+100 seconds
        await increaseTime(100);

        debug(`Transferring ${ethers.utils.formatEther(transferAmount)}...`)
        // now transfer out 500
        await ticket.transfer(wallet2.address, transferAmount);
        timestamp2 = (await getBlock('latest')).timestamp;
        debug(`Transferred at time ${timestamp2}`)

        // they've held 500 for t+100+100 seconds
        await increaseTime(100);
      })

      it('should return an average of zero for pre-history requests', async () => {
        await ticket.getAverageBalanceTx(wallet1.address, timestamp - 100, timestamp - 50)

        debug(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
        expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp - 100, timestamp - 50)).to.equal(toWei('0'));
      });

      it('should return half the minted balance when the duration is centered over first twab', async () => {
        await printTwabs(ticket, wallet1, debug)
        debug(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
        expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp - 50, timestamp + 50)).to.equal(toWei('500'))
      })

      it('should return an accurate average when the range is between twabs', async () => {
        await ticket.getAverageBalanceTx(wallet1.address, timestamp + 50, timestamp + 55)
        debug(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 55}`)
        expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp + 50, timestamp + 55)).to.equal(toWei('1000'))
      })

      it('should return an accurate average when the end is after the last twab', async () => {
        debug(`Test getAverageBalance() : ${timestamp2 - 50}, ${timestamp2 + 50}`)
        expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp2 - 50, timestamp2 + 50)).to.equal(toWei('750'))
      })

      it('should return an accurate average when the range is after twabs', async () => {
        debug(`Test getAverageBalance() : ${timestamp2 + 50}, ${timestamp2 + 51}`)
        expect(await ticket.getAverageBalanceBetween(wallet1.address, timestamp2 + 50, timestamp2 + 51)).to.equal(toWei('500'))
      })
    })
  })

  describe('getAverageBalancesBetween()', () => {
    const debug = newDebug('pt:Ticket.test.ts:getAverageBalancesBetween()')
    const balanceBefore = toWei('1000');
    let timestamp: number

    beforeEach(async () => {
      await ticket.mint(wallet1.address, balanceBefore);
      timestamp = (await getBlock('latest')).timestamp;
      debug(`minted ${ethers.utils.formatEther(balanceBefore)} @ timestamp ${timestamp}`)
      // console.log(`Minted at time ${timestamp}`)
    });
    
    it('should revert on unequal lenght inputs', async () => {
      const drawStartTimestamp = timestamp
      const drawEndTimestamp = timestamp
      await expect(ticket.getAverageBalancesBetween(wallet1.address, [drawStartTimestamp, drawStartTimestamp], [drawEndTimestamp])).
      to.be.revertedWith("Ticket/start-end-times-length-match")
    })

    it('should return an average of zero for pre-history requests', async () => {
      // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
     const drawStartTimestamp = timestamp - 100
     const drawEndTimestamp = timestamp - 50
     const result = await ticket.getAverageBalancesBetween(wallet1.address, [drawStartTimestamp, drawStartTimestamp - 50], [drawEndTimestamp, drawEndTimestamp -50])
     result.forEach((res: any) => {
       expect(res).to.deep.equal(toWei('0'))
     });
   });

   it('should return half the minted balance when the duration is centered over first twab, and zero from before', async () => {
     await increaseTime(100);
     // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
     const drawStartTimestamp0 = timestamp - 100
     const drawEndTimestamp0 = timestamp - 50


     const drawStartTimestamp = timestamp - 50
     const drawEndTimestamp = timestamp + 50
     const result = await ticket.getAverageBalancesBetween(wallet1.address, [drawStartTimestamp, drawStartTimestamp0], [drawEndTimestamp, drawEndTimestamp0])
     expect(result[0]).to.deep.equal(toWei('500'))
     expect(result[1]).to.deep.equal(toWei('0'))
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

      // no-op register for gas usage
      await ticket.getBalanceTx(wallet1.address, timestampBefore)

      expect(await ticket.getBalanceAt(wallet1.address, timestampBefore)).to.equal(balanceBefore);

      const timestampAfter = (await getBlock('latest')).timestamp;

      expect(await ticket.getBalanceAt(wallet1.address, timestampAfter)).to.equal(
        balanceBefore.sub(transferAmount),
      );
    });
  });

  describe('getBalancesAt()', () => {
    it('should get user balances', async () => {
      const mintAmount = toWei('2000');
      const transferAmount = toWei('500');

      await ticket.mint(wallet1.address, mintAmount);
      const mintTimestamp = (await getBlock('latest')).timestamp;

      await increaseTime(10)

      await ticket.transfer(wallet2.address, transferAmount);
      const transferTimestamp = (await getBlock('latest')).timestamp;

      await increaseTime(10)

      const balances = await ticket.getBalancesAt(wallet1.address, [
        mintTimestamp - 1,
        mintTimestamp,
        mintTimestamp + 1,
        transferTimestamp + 2,
      ]);

      expect(balances[0]).to.equal('0');
      // end of block balance is mint amount
      expect(balances[1]).to.equal(mintAmount);
      expect(balances[2]).to.equal(mintAmount);
      expect(balances[3]).to.equal(mintAmount.sub(transferAmount));
    });
  });

  describe('getTotalSupply()', () => {
    const debug = newDebug("pt:Ticket.test.ts:getTotalSupply()")

    context('after a mint', () => {
      const mintAmount = toWei('1000');
      let timestamp: number

      beforeEach(async () => {
        await ticket.mint(wallet1.address, mintAmount);
        timestamp = (await getBlock('latest')).timestamp;
      })

      it('should return 0 before the mint', async () => {
        expect(await ticket.getTotalSupply(timestamp - 50)).to.equal(0)
      })

      it('should return 0 at the time of the mint', async () => {
        expect(await ticket.getTotalSupply(timestamp)).to.equal(mintAmount)
      })

      it('should return the value after the timestamp', async () => {
        const twab = await ticket.getTwab(wallet1.address, 0)
        debug(`twab: `, twab)
        debug(`Checking time ${timestamp + 1}`)
        await increaseTime(10)
        expect(await ticket.getTotalSupply(timestamp + 1)).to.equal(mintAmount)
      })
    })
  });

  describe('getTotalSupplies()', () => {
    const debug = newDebug('pt:Ticket.test.ts:getTotalSupplies()')

    it('should get ticket total supplies', async () => {
      const mintAmount = toWei('2000');
      const burnAmount = toWei('500');

      await ticket.mint(wallet1.address, mintAmount);
      const mintTimestamp = (await getBlock('latest')).timestamp;
      debug(`mintTimestamp: ${mintTimestamp}`)

      await increaseTime(10)

      await ticket.burn(wallet1.address, burnAmount);
      const burnTimestamp = (await getBlock('latest')).timestamp;
      debug(`burnTimestamp: ${burnTimestamp}`)

      const totalSupplies = await ticket.getTotalSupplies([
        mintTimestamp - 1,
        mintTimestamp,
        mintTimestamp + 1,
        burnTimestamp + 1,
      ]);

      expect(totalSupplies[0]).to.equal(toWei('0'));
      expect(totalSupplies[1]).to.equal(mintAmount);
      expect(totalSupplies[2]).to.equal(mintAmount);
      expect(totalSupplies[3]).to.equal(mintAmount.sub(burnAmount));
    });
  });

  describe('delegate()', () => {
    const debug = newDebug('pt:Ticket.test.ts:delegate()')

    it('should allow a user to delegate to another', async () => {
      await ticket.mint(wallet1.address, toWei('100'))

      await ticket.delegate(wallet2.address)
      const timestamp = (await provider.getBlock('latest')).timestamp

      expect(await ticket.delegateOf(wallet1.address)).to.equal(wallet2.address)
      expect(await ticket.getBalanceAt(wallet1.address, timestamp)).to.equal(toWei('0'))
      expect(await ticket.getBalanceAt(wallet2.address, timestamp)).to.equal(toWei('100'))
    })

    it('should clear old delegates if any', async () => {
      await ticket.mint(wallet1.address, toWei('100'))
      const mintTimestamp = (await provider.getBlock('latest')).timestamp
      debug(`mintTimestamp: ${mintTimestamp}`)
      await ticket.delegate(wallet2.address)
      const delegateTimestamp = (await provider.getBlock('latest')).timestamp
      debug(`delegateTimestamp: ${delegateTimestamp}`)


      await ticket.delegate(wallet3.address)
      const secondTimestamp = (await provider.getBlock('latest')).timestamp

      debug(`secondTimestamp: ${secondTimestamp}`)

      debug(`WALLET 2: ${wallet2.address}`)
      await printTwabs(ticket, wallet2, debug)

      debug(`WALLET 3: ${wallet3.address}`)
      await printTwabs(ticket, wallet3, debug)

      expect(await ticket.getBalanceAt(wallet1.address, delegateTimestamp)).to.equal(toWei('0'))
      expect(await ticket.getBalanceAt(wallet2.address, mintTimestamp)).to.equal('0')
      // balance at the end of the block was zero
      expect(await ticket.getBalanceAt(wallet2.address, delegateTimestamp)).to.equal(toWei('100'))

      expect(await ticket.delegateOf(wallet1.address)).to.equal(wallet3.address)
      expect(await ticket.getBalanceAt(wallet1.address, secondTimestamp)).to.equal(toWei('0'))
      expect(await ticket.getBalanceAt(wallet2.address, secondTimestamp)).to.equal(toWei('0'))
      expect(await ticket.getBalanceAt(wallet3.address, secondTimestamp)).to.equal(toWei('100'))
    })

  })
});
