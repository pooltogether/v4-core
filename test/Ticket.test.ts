import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Interface } from 'ethers/lib/utils';

const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;

const increaseTime = async (time: number) => {
    await provider.send('evm_increaseTime', [ time ]);
    await provider.send('evm_mine', []);
};

function printBalances(balances: any) {
    balances = balances.filter((balance: any) => balance.timestamp != 0)
    balances.map((balance: any) => {
        console.log(`Balance @ ${balance.timestamp}: ${ethers.utils.formatEther(balance.balance)}`)
    })
}

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
        it('should transfer tickets', async () => {
            const balanceBefore = toWei('100');

            await ticket.mint(wallet1.address, balanceBefore);
            await increaseTime(60);
            const latestBlockBefore = await provider.getBlock('latest');

            const transferBalance = toWei('50');
            await ticket.transfer(wallet2.address, transferBalance);

            expect(await ticket.getBalance(wallet1.address, latestBlockBefore.timestamp)).to.equal(balanceBefore);

            const latestBlockAfter = await provider.getBlock('latest');

            expect(await ticket.getBalance(wallet1.address, latestBlockAfter.timestamp + 1)).to.equal(transferBalance);
        })

        it('should correctly handle a full buffer', async () => {
            const cardinality = await ticket.CARDINALITY();
            const balanceBefore = toWei('1000');
            await ticket.mint(wallet1.address, balanceBefore);
            const blocks = [];

            let tx;

            for (let i = 0; i < cardinality; i++) {
                tx = await ticket.transfer(wallet2.address, toWei('1'))
                blocks.push(await provider.getBlock('latest'))
            }

            const txReceipt = await provider.getTransactionReceipt(tx.hash);

            console.log('gas consumption', txReceipt.gasUsed.toString());

            // printBalances(await ticket.getBalances(wallet1.address))

            // should have nothing at beginning of time
            expect(await ticket.getBalance(wallet1.address, 0)).to.equal('0');

            // should have 1000 - cardinality at end of time
            let lastTime = blocks[blocks.length - 1].timestamp
            // console.log("lastTime: ", lastTime)
            expect(await ticket.getBalance(wallet1.address, lastTime)).to.equal(toWei('1000').sub(toWei('1').mul(cardinality)))

            // should match each and every change
            for (let i = 0; i < cardinality; i++) {
                let expectedBalance = toWei('1000').sub(toWei('1').mul(i+1))
                let actualBalance = await ticket.getBalance(wallet1.address, blocks[i].timestamp)
                console.log(`Asserting transfer ${i+1} at time ${blocks[i].timestamp} with ${ethers.utils.formatEther(actualBalance)} equals ${ethers.utils.formatEther(expectedBalance)}...`)
                expect(actualBalance).to.equal(expectedBalance)
            }
        })
    });

    describe('claim', async () => {
        let claimable: any

        beforeEach(async () => {
            let IClaimable = await artifacts.readArtifact('IClaimable')
            claimable = await deployMockContract(wallet1, IClaimable.abi)
        })

        it('should pass a zero balance', async () => {
            await claimable.mock.claim.withArgs(wallet1.address, [0], [0], '0x').returns(true)
            await ticket.claim(wallet1.address, claimable.address, [0], '0x')
        })

        it('should pass the actual balance', async () => {
            const mintAmount = toWei('1000');

            await ticket.mint(wallet1.address, mintAmount);

            await increaseTime(60);
            const block = await provider.getBlock('latest');

            await ticket.mint(wallet1.address, mintAmount);

            await claimable.mock.claim.withArgs(wallet1.address, [block.timestamp], [mintAmount], '0x').returns(true)
            await ticket.claim(wallet1.address, claimable.address, [block.timestamp], '0x')
        })
    })
})
