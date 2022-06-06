import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

describe('CpmmLibHarness', () => {
    let cpmmLibHarness: Contract;
    let CpmmLibHarnessFactory: ContractFactory;

    before(async () => {
        CpmmLibHarnessFactory = await ethers.getContractFactory('CpmmLibHarness');
        cpmmLibHarness = await CpmmLibHarnessFactory.deploy();
    });

    describe("getAmountOut()", () => {
        it('should be correct', async () => {
            expect(await cpmmLibHarness.getAmountOut(550, 5000, 10000)).to.equal(990)
        })
    })

    describe('getAmountIn()', () => {
        it('should be correct', async () => {
            expect(await cpmmLibHarness.getAmountIn(990, 5000, 10000)).to.equal(549)
        })
    })
});
