import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { getSigners, provider } = ethers;

describe('overflowSafeComparator', () => {
  let overflowSafeComparator: Contract;
  let currentTimestamp: number;

  beforeEach(async () => {
    currentTimestamp = (await provider.getBlock('latest')).timestamp;

    const overflowSafeComparatorFactory: ContractFactory = await ethers.getContractFactory(
      'OverflowSafeComparatorHarness',
    );
    overflowSafeComparator = await overflowSafeComparatorFactory.deploy();
  });

  describe('lt()', () => {
    it('should compare timestamp a to timestamp b if no overflow', async () => {
      const timestampA = currentTimestamp - 1000;
      const timestampB = currentTimestamp - 100;

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return false if timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp - 1000;
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });

    it('should compare timestamp a to timestamp b if b has overflowed', async () => {
      const timestampA = currentTimestamp - 1000;
      const timestampB = currentTimestamp + 1000

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });

    it('should compare timestamp a to timestamp b if a has overflowed', async () => {
      const timestampA = currentTimestamp + 1000;
      const timestampB = currentTimestamp - 1000

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return false if timestamps have overflowed and timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp + 1000;
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.ltHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });
  });

  describe('lte()', () => {
    it('should compare timestamp a to timestamp b if no overflow', async () => {
      const timestampA = currentTimestamp - 1000;
      const timestampB = currentTimestamp - 100;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return true if timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp - 1000;
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should compare timestamp a to timestamp b if b has overflowed', async () => {
      const timestampA = currentTimestamp - 1000;
      const timestampB = currentTimestamp + 1000;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(false);
    });

    it('should compare timestamp a to timestamp b if a has overflowed', async () => {
      const timestampA = currentTimestamp + 1000;
      const timestampB = currentTimestamp - 1000;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });

    it('should return true if timestamps have overflowed and timestamp a is equal to timestamp b', async () => {
      const timestampA = currentTimestamp + 1000;
      const timestampB = timestampA;

      expect(
        await overflowSafeComparator.lteHarness(timestampA, timestampB, currentTimestamp),
      ).to.equal(true);
    });
  });
});
