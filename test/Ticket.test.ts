import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet } from 'ethers';
import { ethers } from 'hardhat';
import { Interface } from 'ethers/lib/utils';

const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;

const increaseTime = async (time: number) => {
    await provider.send('evm_increaseTime', [ time ]);
    await provider.send('evm_mine', []);
};

describe('Ticket', () => {
    let ticket: Contract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    beforeEach(async () =>{
        [ wallet1, wallet2, wallet3 ] = await getSigners();

        const ticketFactory: ContractFactory = await ethers.getContractFactory("TicketHarness");
        ticket = await ticketFactory.deploy();

        await ticket.initialize(
            'PoolTogether Dai Ticket',
            'PcDAI',
            18
        );
    })

    describe('transfer()', () => {
        it.only('should transfer tickets', async () => {
            const balanceBefore = toWei('100');

            await ticket.mint(wallet1.address, balanceBefore);
            await increaseTime(60);
            const latestBlockBefore = await provider.getBlock('latest');

            console.log('latestBlockBefore', latestBlockBefore.timestamp);

            const transferBalance = toWei('50');
            await ticket.transfer(wallet2.address, transferBalance);

            console.log('balances', await ticket.getBalances(wallet1.address));

            expect(await ticket.getBalance(wallet1.address, latestBlockBefore.timestamp)).to.equal(balanceBefore);

            const latestBlockAfter = await provider.getBlock('latest');

            console.log('latestBlockAfter', latestBlockAfter.timestamp);

            expect(await ticket.getBalance(wallet1.address, latestBlockAfter.timestamp + 1)).to.equal(transferBalance);
        })
    });
})
