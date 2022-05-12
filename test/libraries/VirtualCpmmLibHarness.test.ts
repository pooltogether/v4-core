import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { utils } = ethers;
const { parseEther: toWei } = utils;

describe('VirtualCpmmLibHarness', () => {
    let virtualCpmmLibHarness: Contract;
    let VirtualCpmmLibHarnessFactory: ContractFactory;

    before(async () => {
        VirtualCpmmLibHarnessFactory = await ethers.getContractFactory('VirtualCpmmLibHarness');
        virtualCpmmLibHarness = await VirtualCpmmLibHarnessFactory.deploy();
    });

    describe("newCpmm()", () => {
        it("should have correct LP for one percent slippage", async () => {
          
            const cpmm = await virtualCpmmLibHarness.newCpmm(
                toWei('0.01'),
                toWei('2'),
                '100'
            )

            expect(cpmm.want).to.equal('5000')
            expect(cpmm.have).to.equal('10000')

        })

        it('should have correct LP for ten percent slippage', async () => {
            const cpmm = await virtualCpmmLibHarness.newCpmm(
                toWei('0.1'),
                toWei('2'),
                '100'
            )

            expect(cpmm.want).to.equal('500')
            expect(cpmm.have).to.equal('1000')
        })
    })

    describe("getAmountOut()", () => {
        it('should be correct', async () => {
            expect(await virtualCpmmLibHarness.getAmountOut(550, 5000, 10000)).to.equal(990)
        })
    })

    describe('getAmountIn()', () => {
        it('should be correct', async () => {
            expect(await virtualCpmmLibHarness.getAmountIn(990, 5000, 10000)).to.equal(549)
        })
    })
});
