import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { utils } = ethers;
const { parseEther: toWei } = utils;

describe('LiquidatorLibHarness', () => {
    let liquidatorLibHarness: Contract;
    let LiquidatorLibHarnessFactory: ContractFactory;

    before(async () => {
        LiquidatorLibHarnessFactory = await ethers.getContractFactory('LiquidatorLibHarness');
        liquidatorLibHarness = await LiquidatorLibHarnessFactory.deploy();
    })

    const exchangeRate = toWei('2') // want:have
    const maxSlippage = toWei('0.01') // 1 percent slippage
    const arbTarget = toWei('100')

    describe('computeExchangeRate()', () => {
        it('should have the current exchange rate when no available balance', async () => {
            expect(await liquidatorLibHarness.computeExchangeRate('0')).to.equal(toWei('2'))
        })

        it('should have the expected slippage when arb target is matched', async () => {
            // exchange rate is have / want
            // higher means more USDC per POOL
            expect(await liquidatorLibHarness.computeExchangeRate(toWei('100'))).to.equal('2040199999999999999')
        })

        it('should handle insane available balance amounts', async () => {
            expect(await liquidatorLibHarness.computeExchangeRate(toWei('10000000'))).to.equal('2004001999999999995987985')
        })
    })

    describe('computeExactAmountIn()', () => {
        it('should revert when they request more than what is available', async () => {
            await expect(liquidatorLibHarness.computeExactAmountIn(toWei('100'), toWei('110'))).to.be.revertedWith('insuff balance')
        })

        it('should work when availableBalance exceeds arb target', async () => {
            expect(await liquidatorLibHarness.computeExactAmountIn(toWei('1000'), toWei('100'))).to.equal('41701417848206839039')
        })
    })

    describe('computeExactAmountOut()', () => {
        it('should revert when requesting more than avail', async () => {
            await expect(liquidatorLibHarness.computeExactAmountOut(toWei('100'), toWei('500'))).to.be.revertedWith('insuff balance')
        })
    })

    describe('swapExactAmountIn()', () => {
        it('should swap correctly', async () => {
            await expect(liquidatorLibHarness.swapExactAmountIn(toWei('100'), toWei('45')))
                .to.emit(liquidatorLibHarness, 'SwapResult').withArgs('90981973857634105975')
            expect(await liquidatorLibHarness.computeExchangeRate('10')).to.equal('2003608836952856445')
        })

        it('should revert if there is insufficient balance', async () => {
            await expect(liquidatorLibHarness.swapExactAmountIn(toWei('50'), toWei('100'))).to.be.revertedWith('Whoops! have exceeds available')
        })
    })

    describe('swapExactAmountOut()', () => {
        it('should update the exchange rate', async () => {
            await expect(liquidatorLibHarness.swapExactAmountOut(toWei('100'), toWei('100')))
                .to.emit(liquidatorLibHarness, 'SwapResult').withArgs('49504950495049504950')
            // now that everything has been liquidated, the exchange rate should be driven back down
            expect(await liquidatorLibHarness.computeExchangeRate('0')).to.equal(toWei('2'))
        })

        it('should revert if there is insufficient balance', async () => {
            await expect(liquidatorLibHarness.swapExactAmountOut(toWei('50'), toWei('100')))
                .to.be.revertedWith('Whoops! have exceeds available')
        })
    })

});
