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

    beforeEach(async () => {
        const exchangeRate = toWei('2') // want:have
        const lastSaleTime = '10'
        const deltaRatePerSecond = toWei('0.01') // increases by 1% each second
        const maxSlippage = toWei('0.01')

        await liquidatorLibHarness.setState(
            exchangeRate,
            lastSaleTime,
            deltaRatePerSecond,
            maxSlippage
        )
    })

    describe('computeExchangeRate()', () => {
        it('should start at the current exchange rate when delta time is zero', async () => {
            expect(await liquidatorLibHarness.computeExchangeRate('10')).to.equal(toWei('2'))
        })

        it('should increase the exchange rate by delta time', async () => {
            // 10 seconds, 1 percent each second, => Delta exchange rate = 10% x 2 = 0.2
            // = 2 + 0.2 = 2.2
            expect(await liquidatorLibHarness.computeExchangeRate('20')).to.equal(toWei('2.2'))
        })
    })

    describe('computeExactAmountInAtTime()', () => {
        it('should compute how much can be purchased at time = 0', async () => {
            expect(await liquidatorLibHarness.computeExactAmountInAtTime(toWei('1000'), toWei('100'), '10')).to.equal('50050050050050050049')
        })

        it('should return 0 if available balance is zero', async () => {
            expect(await liquidatorLibHarness.computeExactAmountInAtTime('0', toWei('100'), '10')).to.equal('0')
        })
    })

    describe('computeExactAmountOutAtTime()', () => {
        it('should compute how much can be purchased at time = 0', async () => {
            expect(await liquidatorLibHarness.computeExactAmountOutAtTime(toWei('1000'), toWei('50'), '10')).to.equal('99900099900099900099')
        })

        it('should return 0 if available balance is zero', async () => {
            expect(await liquidatorLibHarness.computeExactAmountOutAtTime('0', toWei('100'), '10')).to.equal('0')
        })
    })

    describe('swapExactAmountInAtTime()', () => {
        it('should swap correctly', async () => {
            await expect(liquidatorLibHarness.swapExactAmountInAtTime(toWei('1000'), toWei('50'), '10'))
                .to.emit(liquidatorLibHarness, 'SwapResult').withArgs('99900099900099900099')
            expect(await liquidatorLibHarness.computeExchangeRate('10')).to.equal('1996005992009988013')
        })

        it('should revert if there is insufficient balance', async () => {
            await expect(liquidatorLibHarness.swapExactAmountInAtTime(toWei('50'), toWei('100'), '10')).to.be.revertedWith('Whoops! have exceeds available')
        })
    })

    describe('swapExactAmountOutAtTime()', () => {
        it('should update the exchange rate', async () => {
            await expect(liquidatorLibHarness.swapExactAmountOutAtTime(toWei('1000'), toWei('1000'), '10'))
                .to.emit(liquidatorLibHarness, 'SwapResult').withArgs('505050505050505050499')
            expect(await liquidatorLibHarness.computeExchangeRate('10')).to.equal(toWei('1.9602'))
        })

        it('should update the last sale timestamp', async () => {
            await liquidatorLibHarness.swapExactAmountOutAtTime(toWei('1000'), toWei('1000'), '20')
            const state = await liquidatorLibHarness.state()
            expect(state.lastSaleTime.toString()).to.equal('20')
        })

        it('should revert if there is insufficient balance', async () => {
            await expect(liquidatorLibHarness.swapExactAmountOutAtTime(toWei('50'), toWei('100'), '10'))
                .to.be.revertedWith('Whoops! have exceeds available')
        })
    })

});
