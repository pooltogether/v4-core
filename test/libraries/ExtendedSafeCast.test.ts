import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { utils } = ethers;
const { parseEther: toWei } = utils;

describe('ExtendedSafeCast', () => {
    let ExtendedSafeCast: Contract;
    let ExtendedSafeCastFactory: ContractFactory;

    before(async () => {
        ExtendedSafeCastFactory = await ethers.getContractFactory('ExtendedSafeCastHarness');
        ExtendedSafeCast = await ExtendedSafeCastFactory.deploy();
    });

    describe('toUint208()', () => {
        it('should return uint256 downcasted to uint208', async () => {
            const value = toWei('1');

            expect(await ExtendedSafeCast.toUint208(value)).to.equal(value);
        });
        it('should fail to return value if value passed does not fit in 208 bits', async () => {
            const value = BigNumber.from(2).pow(209);

            await expect(ExtendedSafeCast.toUint208(value)).to.be.revertedWith(
                "SafeCast: value doesn't fit in 208 bits",
            );
        });
    });
});
