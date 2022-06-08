import { expect } from 'chai';
import { ethers, artifacts } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { deployMockContract } from 'ethereum-waffle';

const { getContractFactory, getSigners, utils } = ethers;
const { parseEther: toWei, parseUnits } = utils;

describe('PrizePoolLiquidator', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let PrizePoolLiquidatorHarnessFactory: ContractFactory;
    let erc20MintableFactory: ContractFactory;
    
    let ticket: Contract;
    let token: Contract;
    let ppl: Contract;
    let pool: Contract;
    let listener: Contract;

    let IPrizePool: any;

    before(async () => {
        [wallet1, wallet2, wallet3] = await getSigners();

        PrizePoolLiquidatorHarnessFactory = await getContractFactory('PrizePoolLiquidatorHarness');
        erc20MintableFactory = await getContractFactory('ERC20Mintable');
        const ListenerStubFactory = await getContractFactory('PrizePoolLiquidatorListenerStub');
        listener = await ListenerStubFactory.deploy();
        ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
        IPrizePool = await artifacts.readArtifact('IPrizePool')
    });
    
    beforeEach(async () => {
        token = await erc20MintableFactory.deploy('Token', 'TOKE');
        pool = await deployMockContract(wallet1, IPrizePool.abi)
        ppl = await PrizePoolLiquidatorHarnessFactory.deploy(wallet1.address)
        await ppl.setPrizePool(
            pool.address,
            wallet2.address,
            token.address,
            parseUnits('0.1', 9),
            parseUnits('0.1', 9),
            parseUnits('1000', 18),
            parseUnits('100', 6)
        )
    })

    describe('setPrizePool()', () => {
        it('should set the prize pool values', async () => {
            expect(
                (
                    await ppl.getLiquidationConfig(pool.address)
                ).map((o: any) => o.toString())
            ).to.deep.equal([
                wallet2.address,
                token.address,
                parseUnits('0.1', 9).toString(),
                parseUnits('0.1', 9).toString()
            ])

            expect(
                (
                    await ppl.getLiquidationState(pool.address)
                ).map((o: any) => o.toString())
            ).to.deep.equal([
                parseUnits('1000', 18).toString(),
                parseUnits('100', 6).toString()
            ])
        })
    })

    describe('availableBalanceOf()', () => {
        it('should return the balance of the prize pool', async () => {
            await pool.mock.captureAwardBalance.returns(toWei('100'))
            expect(await ppl.callStatic.availableBalanceOf(pool.address)).to.equal(toWei('100'))
        })
    })

    describe('nextLiquidationState()', () => {
        it('should return the updated LP given the currently accrued interest', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            expect(
                (
                    await ppl.callStatic.nextLiquidationState(pool.address)
                ).map((o: any) => o.toString())
            ).to.deep.equals([
                '909090909090909090910',
                '110000000'
            ])
        })
    })

    describe('computeExactAmountIn()', () => {
        it('should return the liquidator lib value', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            expect(
                await ppl.callStatic.computeExactAmountIn(pool.address, parseUnits('5', 6))
            ).to.equal('43290043290043290043')
        })
    })

    describe('computeExactAmountOut()', () => {
        it('should return the liquidator lib value', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            expect(
                await ppl.callStatic.computeExactAmountOut(pool.address, parseUnits('4', 18))
            ).to.equal('481879')
        })
    })

    describe('swapExactAmountIn()', () => {
        it('should successfully swap', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            await pool.mock.award.withArgs(wallet1.address, '481879').returns()
            await token.mint(wallet1.address, parseUnits('4', 18))
            await token.approve(ppl.address, parseUnits('4', 18))
            
            await expect(
                ppl.swapExactAmountIn(pool.address, parseUnits('4', 18), '0')
            ).to.emit(ppl, 'Swapped').withArgs(
                pool.address,
                token.address,
                wallet2.address,
                wallet1.address,
                parseUnits('4', 18),
                '481879'
            )

            // tokens should have been sent to the target
            expect(await token.balanceOf(wallet2.address)).to.equal(parseUnits('4', 18))
            // the liquidator state should have updated
            expect(
                (await ppl.getLiquidationState(pool.address)).map((o: any) => o.toString())
            ).to.deep.equal(['834469157606508972358', '99999999'])
        })

        it('should fail if the user isnt getting enough tokens', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            await expect(
                ppl.swapExactAmountIn(pool.address, parseUnits('4', 18), '481880')
            ).to.be.revertedWith('trade does not meet min')
        })
    })

    describe('swapExactAmountOut()', () => {
        it('should successfully swap', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            await pool.mock.award.withArgs(wallet1.address, parseUnits('5', 6)).returns()
            await token.mint(wallet1.address, '43290043290043290043')
            await token.approve(ppl.address, '43290043290043290043')
            
            await expect(
                ppl.swapExactAmountOut(pool.address, parseUnits('5', 6), '43290043290043290043')
            ).to.emit(ppl, 'Swapped').withArgs(
                pool.address,
                token.address,
                wallet2.address,
                wallet1.address,
                '43290043290043290043',
                parseUnits('5', 6)
            )

            // tokens should have been sent to the target
            expect(await token.balanceOf(wallet2.address)).to.equal("43290043290043290043")
            // the liquidator state should have updated
            expect(
                (await ppl.getLiquidationState(pool.address)).map((o: any) => o.toString())
            ).to.deep.equal(['915729942583732057416', '99999999'])
        })

        it('should fail if the user isnt getting enough tokens', async () => {
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            await expect(
                ppl.swapExactAmountOut(pool.address, parseUnits('5', 6), '43290043290043290042')
            ).to.be.revertedWith('trade does not meet max')
        })

        it('should trigger the listener', async () => {
            await ppl.setListener(listener.address)
            await pool.mock.getTicket.returns(ticket.address)
            
            await pool.mock.captureAwardBalance.returns(parseUnits('10', 6))
            await pool.mock.award.withArgs(wallet1.address, parseUnits('5', 6)).returns()
            await token.mint(wallet1.address, '43290043290043290043')
            await token.approve(ppl.address, '43290043290043290043')
            
            await expect(
                ppl.swapExactAmountOut(pool.address, parseUnits('5', 6), '43290043290043290043')
            ).to.emit(listener, 'AfterSwap').withArgs(
                pool.address,
                ticket.address,
                parseUnits('5', 6),
                token.address,
                '43290043290043290043'
            )
        })
    })

    describe('setListener()', () => {
        it('should allow the manager to set the listener', async () => {
            await ppl.setManager(wallet3.address)
            await ppl.connect(wallet3).setListener(listener.address)
            expect(await ppl.getListener()).to.equal(listener.address)
        })
    })
})
