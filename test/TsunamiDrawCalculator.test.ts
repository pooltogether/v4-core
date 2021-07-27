import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet, BigNumber } from 'ethers';
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

describe('TsunamiDrawCalculator', () => {
    let drawCalculator: Contract; let ticket: MockContract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    
    let draw: any
    const encoder = ethers.utils.defaultAbiCoder

    beforeEach(async () =>{
        [ wallet1, wallet2, wallet3 ] = await getSigners();
        const drawCalculatorFactory = await ethers.getContractFactory("TsunamiDrawCalculatorHarness")
        drawCalculator = await drawCalculatorFactory.deploy()

        let ticketArtifact = await artifacts.readArtifact('ITicket')
        ticket = await deployMockContract(wallet1, ticketArtifact.abi)

        const matchCardinality = 8
        const prizeRange = 10
        await drawCalculator.initialize(ticket.address, matchCardinality, [ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")], prizeRange)

    })

    describe('admin functions', ()=>{
        it('onlyOwner should set matchCardinality', async ()=>{
            expect(await drawCalculator.setMatchCardinality(5)).
                to.emit(drawCalculator, "MatchCardinalitySet").
                withArgs(5)
            await expect(drawCalculator.connect(wallet2).setMatchCardinality(5)).to.be.reverted
        })

        it('onlyOwner should set range', async ()=>{
            expect(await drawCalculator.setNumberRange(5)).
                to.emit(drawCalculator, "PrizeRangeSet").
                withArgs(5)
            await expect(drawCalculator.connect(wallet2).setNumberRange(5)).to.be.reverted
        })
        
        it('onlyOwner set prize distributions', async ()=>{
            expect(await drawCalculator.setPrizeDistribution([ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")])).
                to.emit(drawCalculator, "PrizeDistributionsSet")
            await expect(drawCalculator.connect(wallet2).setPrizeDistribution([ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")])).to.be.reverted
        })

        it('cannot set over 100pc of prize for distribution', async ()=>{
            await expect(drawCalculator.setPrizeDistribution([ethers.utils.parseEther("0.9"), ethers.utils.parseEther("0.2")])).to.be.revertedWith("sum of distributions too large")
        })
    })

    describe('getValueAtIndex()', ()=>{
        it('should return the value at 0 index with full range, no bias', async ()=>{
            const result = await drawCalculator.callStatic.getValueAtIndex("63","0","16")
            expect(result).to.equal(15)
        })
        it('should return the value at 1 index with full range, no bias', async ()=>{
            const result = await drawCalculator.callStatic.getValueAtIndex("63","1","15")
            expect(result).to.equal(3)
        })
        it('should return the value at 1 index with full range, no bias', async ()=>{
            const result = await drawCalculator.callStatic.getValueAtIndex("64","1","15")
            expect(result).to.equal(4)
        })
        it('should return the value at 0 index with half range', async ()=>{
            const result = await drawCalculator.callStatic.getValueAtIndex("63","0","7")
            expect(result).to.equal(1) // 15 % 7
        })
        it('should return the value at 0 index with 1 range', async ()=>{
            const result = await drawCalculator.callStatic.getValueAtIndex("63","0","1")
            expect(result).to.equal(0) // 15 % 1
        })
        it('should return the value at 0 index with half range', async ()=>{
            const result = await drawCalculator.callStatic.getValueAtIndex("63","0","10")
            expect(result).to.equal(5) // 15 % 10
        })
    })

    describe('calculate()', () => {
        it('should calculate and win grand prize', async () => {
            //function calculate(address user, uint256[] calldata randomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external override view returns (uint256){

            const winningNumber = utils.solidityKeccak256(["address"], [wallet1.address])//"0x1111111111111111111111111111111111111111111111111111111111111111"
            // console.log("winningNumber in test", winningNumber)
            const winningRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
            // console.log("winningRandomNumber in test", winningRandomNumber)

            const timestamp = 42
            const prizes = [utils.parseEther("100")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
            const ticketBalance = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance

            expect(await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )).to.equal(utils.parseEther("80"))
            
            console.log("GasUsed for calculate(): ", (await drawCalculator.estimateGas.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices)).toString())
        })

        it('should calculate and win nothing', async () => {
            //function calculate(address user, uint256[] calldata winningRandomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data)

            const winningNumber = utils.solidityKeccak256(["address"], [wallet2.address])
            // console.log("winningNumber in test", winningNumber)
            const userRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
            console.log("userRandomNumber in test", userRandomNumber)

            const timestamp = 42
            const prizes = [utils.parseEther("100")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
            const ticketBalance = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance

            expect(await drawCalculator.calculate(
                wallet1.address,
                [userRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )).to.equal(utils.parseEther("0"))
        })

        it('increasing the matchCardinality for same user and winning numbers results in less of a prize', async () => {
            //function calculate(address user, uint256[] calldata winningRandomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data)
            const timestamp = 42
            const prizes = [utils.parseEther("100")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
            const ticketBalance = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance
            
            await drawCalculator.setPrizeDistribution([
                ethers.utils.parseEther("0.2"),
                ethers.utils.parseEther("0.1"),
                ethers.utils.parseEther("0.1"),
                ethers.utils.parseEther("0.1")
            ])
            
            await drawCalculator.setMatchCardinality(6)
            await drawCalculator.setNumberRange(4)

            const winningRandomNumber = "0x3fa0adea2a0c897d68abddf4f91167acda84750ee4a68bf438860114c8592b35"
            const resultingPrize = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize).to.equal(ethers.BigNumber.from(utils.parseEther("0.625")))
            // now increase cardinality 
            await drawCalculator.setMatchCardinality(7)
            const resultingPrize2 = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize2).to.equal(ethers.BigNumber.from(utils.parseEther("0.15625")))
        })

        it.only('increasing the number range results in lower probability of matches', async () => {
            //function calculate(address user, uint256[] calldata winningRandomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data)
            const timestamp = 42
            const prizes = [utils.parseEther("100")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
            const ticketBalance = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance
            
            // increasing the distribution array length should make it easier to get a match
            await drawCalculator.setPrizeDistribution([
                ethers.utils.parseEther("0.2"),
                ethers.utils.parseEther("0.1"),
                ethers.utils.parseEther("0.1"),
                ethers.utils.parseEther("0.1")
            ])
            
            await drawCalculator.setMatchCardinality(5)
            await drawCalculator.setNumberRange(4) // this means from 0 to 4 is available for matching

            const winningRandomNumber = "0x4e0664ee1b7cb711b9b899f90869149727cdfde6d7c96b0916254cdae743abac" // number of matches = 3
            const resultingPrize = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize).to.equal(ethers.BigNumber.from(utils.parseEther("0.625")))

            // now increase number range 
            await drawCalculator.setNumberRange(6) // this means from 0 to 6 is available for matching
            const winningRandomNumber2 = "0x7693f99d82f3d80754b9afafca8af693fb1487fbc7b126f15b97ba76ee848557" // number of matches = 2 
            const resultingPrize2 = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber2],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize2).to.equal(ethers.BigNumber.from(utils.parseEther("0.0462962962962962")))
        })
    });
})
