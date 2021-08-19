import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { utils, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { getSigners } = ethers;
const { parseEther: toWei } = utils;

describe('TwabLibrary', () => {
  let cardinality: number;
  let twabLib: Contract;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;

  beforeEach(async () => {
    [wallet1, wallet2] = await getSigners();

    const twabLibFactory: ContractFactory = await ethers.getContractFactory('TwabLibraryExposed');
    twabLib = await twabLibFactory.deploy();
    cardinality = await twabLib.MAX_CARDINALITY();
  });

  describe('getAverageBalanceBetween()', () => {

    context('with one twab', () => {
      const currentBalance = toWei('1000');
      let timestamp = 1000
      let currentTime = 2000

      beforeEach(async () => {
        await twabLib.setTwabs([{ amount: 0, timestamp }])
      });
  
      it('should return an average of zero for pre-history requests', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
        expect(await twabLib.getAverageBalanceBetween(currentBalance, 0, timestamp - 100, timestamp - 50, cardinality, currentTime)).to.equal(toWei('0'));
      });

      it('should return an average of zero for pre-history requests when including the first twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
        expect(await twabLib.getAverageBalanceBetween(currentBalance, 0, timestamp - 100, timestamp, cardinality, currentTime)).to.equal(toWei('0'));
      });
  
      it('should not project into the future', async () => {
        // at this time the user has held 1000 tokens for zero seconds
        // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
        expect(await twabLib.getAverageBalanceBetween(currentBalance, 0, timestamp - 50, timestamp + 50, cardinality, timestamp)).to.equal(toWei('0'))
      })
  
      it('should return half the minted balance when the duration is centered over first twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
        expect(await twabLib.getAverageBalanceBetween(currentBalance, 0, timestamp - 50, timestamp + 50, cardinality, currentTime)).to.equal(toWei('500'))
      })
  
      it('should return an accurate average when the range is after the last twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 51}`)
        expect(await twabLib.getAverageBalanceBetween(currentBalance, 0, timestamp + 50, timestamp + 51, cardinality, currentTime)).to.equal(toWei('1000'))
      })
    })

    context('with two twabs', () => {
      const mintAmount = toWei('1000');
      const transferAmount = toWei('500')
      let timestamp1 = 1000
      let timestamp2 = 2000
      let currentTime = 3000

      let twabs = [
        { amount: 0, timestamp: timestamp1 }, // minted
        { amount: (mintAmount.mul(timestamp2 - timestamp1)), timestamp: timestamp2 } // transferred
      ]

      beforeEach(async () => {
        await twabLib.setTwabs(twabs)
      })

      it('should return an average of zero for pre-history requests', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
        expect(await twabLib.getAverageBalanceBetween(mintAmount.sub(transferAmount), twabs.length - 1, timestamp1 - 100, timestamp1 - 50, cardinality, currentTime)).to.equal(toWei('0'));
      });

      it('should return half the minted balance when the duration is centered over first twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
        expect(await twabLib.getAverageBalanceBetween(mintAmount.sub(transferAmount), twabs.length - 1, timestamp1 - 50, timestamp1 + 50, cardinality, currentTime)).to.equal(toWei('500'))
      })

      it('should return an accurate average when the range is between twabs', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 55}`)
        expect(await twabLib.getAverageBalanceBetween(mintAmount.sub(transferAmount), twabs.length - 1, timestamp1 + 50, timestamp1 + 55, cardinality, currentTime)).to.equal(toWei('1000'))
      })

      it('should return an accurate average when the end is after the last twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp2 - 50}, ${timestamp2 + 50}`)
        expect(await twabLib.getAverageBalanceBetween(mintAmount.sub(transferAmount), twabs.length - 1, timestamp2 - 50, timestamp2 + 50, cardinality, currentTime)).to.equal(toWei('750'))
      })

      it('should return an accurate average when the range is after twabs', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp2 + 50}, ${timestamp2 + 51}`)
        expect(await twabLib.getAverageBalanceBetween(mintAmount.sub(transferAmount), twabs.length - 1, timestamp2 + 50, timestamp2 + 51, cardinality, currentTime)).to.equal(toWei('500'))
      })
    })
  })

  describe('getBalanceAt', () => {

    context('with one twab', () => {
      const currentBalance = toWei('1000');
      let timestamp = 1000
      let currentTime = 2000

      beforeEach(async () => {
        await twabLib.setTwabs([{ amount: 0, timestamp }])
      });

      it('should return 0 for time before history', async () => {
        expect(await twabLib.getBalanceAt(500, currentBalance, 0, cardinality, currentTime)).to.equal(0)
      })

      it('should return 0 for twab timestamp', async () => {
        expect(await twabLib.getBalanceAt(timestamp, currentBalance, 0, cardinality, currentTime)).to.equal(0)
      })

      it('should return the current balance after the twab', async () => {
        expect(await twabLib.getBalanceAt(1500, currentBalance, 0, cardinality, currentTime)).to.equal(currentBalance)
      })
    })

    context('with two twabs', () => {
      const mintAmount = toWei('1000');
      const transferAmount = toWei('500')
      const currentBalance = toWei('500')

      let timestamp1 = 1000
      let timestamp2 = 2000
      let currentTime = 3000

      let twabs = [
        { amount: 0, timestamp: timestamp1 }, // minted
        { amount: (mintAmount.mul(timestamp2 - timestamp1)), timestamp: timestamp2 } // transferred
      ]

      beforeEach(async () => {
        await twabLib.setTwabs(twabs)
      })

      it('should return zero when request before first twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 100}, ${timestamp - 50}`)
        expect(await twabLib.getBalanceAt(timestamp1 - 100, currentBalance, twabs.length - 1, cardinality, currentTime)).to.equal(toWei('0'));
      });

      it('should return zero when request is on first twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp - 50}, ${timestamp + 50}`)
        expect(await twabLib.getBalanceAt(timestamp1, currentBalance, twabs.length - 1, cardinality, currentTime)).to.equal(toWei('0'))
      })
/*
      | |   < >
      | < | >
      | <| >
      < | | >
      < | > |
      < > | |
*/
      it('should return when around the first twab', async () => {

      })

      it('should return mint amount when between twabs', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp + 50}, ${timestamp + 55}`)
        expect(await twabLib.getBalanceAt(timestamp1 + 50, currentBalance, twabs.length - 1, cardinality, currentTime)).to.equal(mintAmount)
      })

      it('should return mint amount when on last twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp2 - 50}, ${timestamp2 + 50}`)
        expect(await twabLib.getBalanceAt(timestamp2, currentBalance, twabs.length - 1, cardinality, currentTime)).to.equal(mintAmount)
      })

      it('should return current balance when after last twab', async () => {
        // console.log(`Test getAverageBalance() : ${timestamp2 + 50}, ${timestamp2 + 51}`)
        expect(await twabLib.getBalanceAt(timestamp2 + 50, currentBalance, twabs.length - 1, cardinality, currentTime)).to.equal(currentBalance)
      })
    })
  
  })

  describe('wrapCardinality()', () => {
    it('should ensure an out of bounds index is wrapped', async () => {
      expect(await twabLib.wrapCardinality(11, 5)).to.equal(1)
    })

    it('should ensure an in-bounds index is not wrapped', async () => {
      expect(await twabLib.wrapCardinality(0, 10)).to.equal(0)
    })
  })

  describe('mostRecentIndex()', () => {
    it('should return the most recent active twab, given the next available one', async () => {
      let nextAvailableTwabIndex = 0; // next one is the beginning, so we have to wrap backwards
      expect(await twabLib.mostRecentIndex(nextAvailableTwabIndex, 3)).to.equal(2)
    })
  })

  describe('nextTwab()', () => {
    it('should correctly calculate the next twab and index', async () => {
      let currentTwab = { amount: 1000, timestamp: 1000 }
      let currentBalance = 2000
      let currentTime = 3000
      const newTwab = await twabLib.nextTwab(currentTwab, currentBalance, currentTime)
    })
  })

  describe('calculateNextWithExpiry()', () => {

    context('with no twabs', () => {
      // it('should ')
    })

    const mintAmount = toWei('1000');
    const transferAmount = toWei('500')
    const currentBalance = toWei('500')

    let timestamp1 = 1000
    let timestamp2 = 2000
    let currentTime = 3000

    let twabs = [
      { amount: 0, timestamp: timestamp1 }, // minted
      { amount: (mintAmount.mul(timestamp2 - timestamp1)), timestamp: timestamp2 } // transferred
    ]

    beforeEach(async () => {
      await twabLib.setTwabs(twabs)
    })

    
  })

  describe('nextTwabWithExpiry()', () => {
  })
});
