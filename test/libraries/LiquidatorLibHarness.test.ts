import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { utils } = ethers;
const { parseEther: toWei, parseUnits, formatUnits } = utils;

describe('LiquidatorLibHarness', () => {
    let liquidatorLibHarness: Contract;
    let LiquidatorLibHarnessFactory: ContractFactory;

    before(async () => {
        LiquidatorLibHarnessFactory = await ethers.getContractFactory('LiquidatorLibHarness');
        liquidatorLibHarness = await LiquidatorLibHarnessFactory.deploy();
    })

    let reserveA = parseUnits('1000', 18)
    let reserveB = parseUnits('100', 6)
    let availableReserveB = parseUnits('10', 6)
    let swapMultiplier = parseUnits('0.1', 9)
    let liquidityFraction = parseUnits('0.1', 9)

    describe('prepareSwap()', () => {
        it('should increase the buy power of reserveA', async () => {
            // swapping reserve b for reserve a
            // (x + a) * (y - b) = x * y
            // xy - xb + ay - ab = xy
            // xy + ay - (xb + ab) = xy
            // ay - b(x + a) = 0
            // ay / (x + a) = b
            //
            // x = reserve b
            // a = avail reserve b
            // y = reserve a
            // b = amount of reserve b
            // (10e6 * 1000e18) / (100e6 + 10e6) = 90909090909090900000
            // => new y = y - b = 909090909090909100000
            // => new x = (x + a) = 110
            expect(
                (await liquidatorLibHarness.prepareSwap(
                    reserveA,
                    reserveB,
                    availableReserveB
                )).map((o: any) => o.toString())
            ).to.deep.equal([
                '909090909090909090910',
                '110000000'
            ])
        })

        it('should do nothing if there is no reserve', async () => {
            expect(
                (await liquidatorLibHarness.prepareSwap(
                    reserveA,
                    reserveB,
                    '0'
                )
                ).map((o: any) => o.toString())
            ).to.deep.equal([
                reserveA.toString(),
                reserveB.toString()
            ])
        })
    })

    describe('computeExactAmountIn()', () => {
        it('should revert when they request more than what is available', async () => {
            let amountOutB = parseUnits('101', 6)
            await expect(liquidatorLibHarness.computeExactAmountIn(
                reserveA,
                reserveB,
                availableReserveB,
                amountOutB
            )).to.be.revertedWith('insuff balance')
        })

        it('should work', async () => {
            // we know from the prepareSwap test that the LP will be:
            // reserveA: 909090909090909090910
            // reserveB: 110000000
            // so let's recompute from there

            // we're swapping a of x for b of y:
            // ay = (xb + ab)
            // solve for a:
            // a(y - b) = xb
            // a = (xb) / (y - b)
            // x = reserve a
            // y = reserve b
            // a = amountInA
            // b = amountOutB
            // a = (909090909090909090910*5e6) / (110000000 - 5e6) = 43290043290043290000

            let amountOutB = parseUnits('5', 6)
            expect(
                await liquidatorLibHarness.computeExactAmountIn(
                    reserveA,
                    reserveB,
                    availableReserveB,
                    amountOutB
                )
            ).to.equal('43290043290043290043')
        })
    })

    describe('computeExactAmountOut()', () => {
        it('should revert when requesting more than avail', async () => {
            let amountInA = parseUnits('101', 18)
            await expect(
                liquidatorLibHarness.computeExactAmountOut(
                    reserveA,
                    reserveB,
                    availableReserveB,
                    amountInA
                )
            ).to.be.revertedWith('insuff balance')
        })

        it('should work', async () => {
            let amountInA = parseUnits('4', 18)
            // we know from the prepareSwap test that the LP will be:
            // reserveA: 909090909090909090910
            // reserveB: 110000000
            // so let's recompute from there

            // we're swapping A for B
            // ay / (x + a) = b
            // x = reserve a
            // y = reserve b
            // a = amountInA
            // b = amountOut
            // (4e18*110000000) / (909090909090909090910 + 4e18) = 481879

            expect(
                await liquidatorLibHarness.computeExactAmountOut(
                    reserveA,
                    reserveB,
                    availableReserveB,
                    amountInA
                )
            ).to.equal('481879')
        })
    })

    describe('swapExactAmountIn()', () => {
        it('should fail if there are insufficient funds', async () => {
            await expect(
                liquidatorLibHarness.swapExactAmountIn(
                    reserveA,
                    reserveB,
                    '1',
                    parseUnits('1000', 18),
                    swapMultiplier,
                    liquidityFraction
                )
            ).to.be.revertedWith('LiqLib/insuff-liq')
        })

        it('should swap correctly', async () => {
            let amountInA = parseUnits('4', 18)
            // we know that the user will get 481879
            // new LP would be:
            // reserveA = 909090909090909090910 + 4e18 = 913090909090909100000
            // reserveB = 110000000 - 481879 = 109518121
            
            // Now we need to apply the swap multiplier.
            // it's applied to the output amount, so deepen do a second swap with the desired amount out B
            // const swapMultiplierOutB = ethers.BigNumber.from('481879').mul(swapMultiplier).div(1e9)
            // console.log(swapMultiplierOutB.toString())
            // a = (xb) / (y - b)
            // x = reserve a
            // y = reserve b
            // a = amountInA
            // b = swapMultiplierOutB = 48187
            // a = (913090909090909100000*48187) / (109518121 - 48187) = 401928730827257400
            // New LP is:
            // reserveA = 913090909090909100000 + 401928730827257400 = 913492837821736400000
            // reserveB = 109518121 - 48187 = 109469934

            // now adjust LP so that reserveB is liquidityFraction
            // interest is 10e6, and lf is 0.1 so we expect liquidity to be 10e7
            // multiplier = 10e7 / 109469934 = 0.913492831739535
            // so our new LP should be:
            // reserveA: 913492837821736400000*multiplier = 834469159195561800000
            // reserveB: 10e7

            expect(
                (await liquidatorLibHarness.swapExactAmountIn(
                    reserveA,
                    reserveB,
                    availableReserveB,
                    amountInA,
                    swapMultiplier,
                    liquidityFraction
                )).map((o: any) => o.toString())
            ).to.deep.equal([
                '834469157606508972358',
                '99999999',
                '481879'
            ])
        })
    })

    describe('swapExactAmountOut()', () => {
        it('should fail if there are insufficient funds', async () => {
            await expect(
                liquidatorLibHarness.swapExactAmountOut(
                    reserveA,
                    reserveB,
                    '1',
                    '2',
                    swapMultiplier,
                    liquidityFraction
                )
            ).to.be.revertedWith('LiqLib/insuff-liq')
        })

        it('should swap correctly', async () => {
            let amountOutB = parseUnits('5', 6)
            // we know that the user will pay 43290043290043290043
            // new LP would be:
            // reserveA = 909090909090909090910 + 43290043290043290043 = 952380952380952400000
            // reserveB = 110000000 - 5e6 = 105000000
            
            // Now we need to apply the swap multiplier.
            // it's applied to the output amount, so deepen do a second swap with the desired amount out B
            // const swapMultiplierOutB = ethers.BigNumber.from(5e6).mul(swapMultiplier).div(1e9)
            // console.log(swapMultiplierOutB.toString())
            // a = (xb) / (y - b)
            // x = reserve a
            // y = reserve b
            // a = amountInA
            // b = swapMultiplierOutB = 500000
            // a = (952380952380952400000*500000) / (105000000 - 500000) = 4556846662109820000
            // New LP is:
            // reserveA = 952380952380952400000 + 4556846662109820000 = 956937799043062200000
            // reserveB = 105000000 - 500000 = 104500000

            // now adjust LP so that reserveB is liquidityFraction
            // interest is 10e6, and lf is 0.1 so we expect liquidity to be 10e7
            // multiplier = 10e7 / 104500000 = 0.9569377990430622
            // so our new LP should be:
            // reserveA: 956937799043062200000*multiplier = 915729951237380100000
            // reserveB: 10e7

            expect(
                (await liquidatorLibHarness.swapExactAmountOut(
                    reserveA,
                    reserveB,
                    availableReserveB,
                    amountOutB,
                    swapMultiplier,
                    liquidityFraction
                )).map((o: any) => o.toString())
            ).to.deep.equal([
                '915729942583732057416',
                '99999999',
                '43290043290043290043'
            ])
        })


    })

})
