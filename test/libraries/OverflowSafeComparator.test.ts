import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { getSigners } = ethers;

describe.skip('overflowSafeComparator', () => {
  let overflowSafeComparator: Contract;

  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;

  let currentTimestamp: number;

  beforeEach(async () => {
    [wallet1, wallet2] = await getSigners();

    currentTimestamp = 1620084438 // 5/3/2021 - 23:27:18

    const overflowSafeComparatorFactory: ContractFactory = await ethers.getContractFactory(
      'OverflowSafeComparatorHarness',
    );
    overflowSafeComparator = await overflowSafeComparatorFactory.deploy();
  });

  describe('lt()', () => {
    it('should compare timestamp a to timestamp b if no overflow', async () => {
      const timestampA = currentTimestamp - Math.floor(Math.random() * 1000);
      const timestampB = currentTimestamp - Math.floor(Math.random() * 100);

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return false if timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp - Math.floor(Math.random() * 1000);
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });

    it('should compare timestamp a to timestamp b if b has overflowed', async () => {
      const timestampA = currentTimestamp - Math.floor(Math.random() * 1000);
      const timestampB = currentTimestamp + Math.floor(Math.random() * 1000);

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });

    it('should compare timestamp a to timestamp b if a has overflowed', async () => {
      const timestampA = currentTimestamp + Math.floor(Math.random() * 1000);
      const timestampB = currentTimestamp - Math.floor(Math.random() * 1000);

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return false if timestamps have overflowed and timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp + Math.floor(Math.random() * 1000);
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });
  });

  describe('lte()', () => {
    it('should compare timestamp a to timestamp b if no overflow', async () => {
      const timestampA = currentTimestamp - Math.floor(Math.random() * 1000);
      const timestampB = currentTimestamp - Math.floor(Math.random() * 100);

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return true if timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp - Math.floor(Math.random() * 1000);
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should compare timestamp a to timestamp b if b has overflowed', async () => {
      const timestampA = currentTimestamp - Math.floor(Math.random() * 1000);
      const timestampB = currentTimestamp + Math.floor(Math.random() * 1000);

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });

    it('should compare timestamp a to timestamp b if a has overflowed', async () => {
      const timestampA = currentTimestamp + Math.floor(Math.random() * 1000);
      const timestampB = currentTimestamp - Math.floor(Math.random() * 1000);

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return true if timestamps have overflowed and timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp + Math.floor(Math.random() * 1000);
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });
  });
});
