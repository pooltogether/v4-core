import { Signer } from '@ethersproject/abstract-signer';
import { SignatureLike } from '@ethersproject/bytes';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { utils, Contract, ContractFactory } from 'ethers';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import hre, { ethers } from 'hardhat';

import { delegateSignature } from '../helpers/delegateSignature';
import { signPermit } from '../helpers/signPermit';

const { constants, getContractFactory, getSigners, provider } = ethers;
const { AddressZero } = constants;
const { artifacts } = hre;
const { getNetwork } = provider;
const { parseEther: toWei, splitSignature } = utils;

describe('EIP2612PermitAndDeposit', () => {
    let wallet: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let prizeStrategyManager: SignerWithAddress;

    let permitAndDeposit: Contract;
    let usdc: Contract;
    let PrizePoolHarness: ContractFactory;
    let prizePool: Contract;
    let ticket: Contract;
    let yieldSourceStub: MockContract;

    let chainId: number;

    type EIP2612PermitAndDepositToAndDelegate = {
        prizePool: string;
        fromWallet?: SignerWithAddress;
        to: string;
        amount: string;
        delegateAddress: string;
    };

    async function permitAndDepositToAndDelegate({
        prizePool,
        fromWallet,
        to,
        amount,
        delegateAddress,
    }: EIP2612PermitAndDepositToAndDelegate) {
        if (!fromWallet) {
            fromWallet = wallet;
        }

        const { user, delegate, deadline, v, r, s } = await delegateSignature({
            ticket,
            userWallet: fromWallet,
            delegate: delegateAddress,
        });

        const delegateSign: SignatureLike = { v, r, s };

        const permit = await signPermit(
            fromWallet,
            {
                name: 'USD Coin',
                version: '1',
                chainId,
                verifyingContract: usdc.address,
            },
            {
                owner: user,
                spender: permitAndDeposit.address,
                value: amount,
                nonce: 0,
                deadline,
            },
        );

        const permitSignature = splitSignature(permit.sig);

        return permitAndDeposit.permitAndDepositToAndDelegate(
            user,
            amount,
            deadline,
            permitSignature,
            delegateSign,
            prizePool,
            to,
            delegate,
        );
    }

    beforeEach(async () => {
        [wallet, wallet2, prizeStrategyManager] = await getSigners();

        const network = await getNetwork();
        chainId = network.chainId;

        const Usdc = await getContractFactory('EIP2612PermitMintable');
        usdc = await Usdc.deploy('USD Coin', 'USDC');

        const YieldSourceStub = await artifacts.readArtifact('YieldSourceStub');
        yieldSourceStub = await deployMockContract(wallet as Signer, YieldSourceStub.abi);
        await yieldSourceStub.mock.depositToken.returns(usdc.address);

        PrizePoolHarness = await getContractFactory('PrizePoolHarness', wallet);
        prizePool = await PrizePoolHarness.deploy(wallet.address, yieldSourceStub.address);

        const EIP2612PermitAndDeposit = await getContractFactory('EIP2612PermitAndDeposit');
        permitAndDeposit = await EIP2612PermitAndDeposit.deploy();

        const Ticket = await getContractFactory('TicketHarness');
        ticket = await Ticket.deploy('PoolTogether Usdc Ticket', 'PcUSDC', 18, prizePool.address);

        await prizePool.setTicket(ticket.address);
        await prizePool.setPrizeStrategy(prizeStrategyManager.address);
    });

    describe('permitAndDepositToAndDelegate()', () => {
        it('should deposit and delegate to itself', async () => {
            const amount = toWei('100');

            await usdc.mint(wallet.address, toWei('1000'));

            await yieldSourceStub.mock.supplyTokenTo.withArgs(amount, prizePool.address).returns();

            await permitAndDepositToAndDelegate({
                prizePool: prizePool.address,
                to: wallet.address,
                amount: '100000000000000000000',
                delegateAddress: wallet.address,
            });

            expect(await usdc.balanceOf(prizePool.address)).to.equal(amount);
            expect(await usdc.balanceOf(wallet.address)).to.equal(toWei('900'));
            expect(await ticket.balanceOf(wallet.address)).to.equal(amount);
            expect(await ticket.delegateOf(wallet.address)).to.equal(wallet.address);
        });

        it('should deposit and delegate to someone else', async () => {
            const amount = toWei('100');

            await usdc.mint(wallet.address, toWei('1000'));

            await yieldSourceStub.mock.supplyTokenTo.withArgs(amount, prizePool.address).returns();

            await permitAndDepositToAndDelegate({
                prizePool: prizePool.address,
                to: wallet.address,
                amount: '100000000000000000000',
                delegateAddress: wallet2.address,
            });

            expect(await usdc.balanceOf(prizePool.address)).to.equal(amount);
            expect(await usdc.balanceOf(wallet.address)).to.equal(toWei('900'));
            expect(await ticket.balanceOf(wallet.address)).to.equal(amount);
            expect(await ticket.balanceOf(wallet2.address)).to.equal(toWei('0'));
            expect(await ticket.delegateOf(wallet.address)).to.equal(wallet2.address);
            expect(await ticket.delegateOf(wallet2.address)).to.equal(AddressZero);
        });

        it('should not allow anyone else to use the signature', async () => {
            const amount = toWei('100');

            await usdc.mint(wallet.address, toWei('1000'));

            await yieldSourceStub.mock.supplyTokenTo.withArgs(amount, prizePool.address).returns();

            await expect(
                permitAndDepositToAndDelegate({
                    prizePool: prizePool.address,
                    to: wallet2.address,
                    fromWallet: wallet2,
                    amount: '100000000000000000000',
                    delegateAddress: wallet2.address,
                }),
            ).to.be.revertedWith('EIP2612PermitAndDeposit/only-signer');
        });
    });
});
