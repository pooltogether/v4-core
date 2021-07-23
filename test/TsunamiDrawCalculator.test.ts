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

describe('TsunamiDrawCalculator', () => {
    let drawCalculator: Contract; let ticket: MockContract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    
    let draw: any
    const encoder = ethers.utils.defaultAbiCoder

    beforeEach(async () =>{
        [ wallet1, wallet2, wallet3 ] = await getSigners();
        const drawCalculatorFactory = await ethers.getContractFactory("TsunamiDrawCalculator")
        drawCalculator = await drawCalculatorFactory.deploy()

        let ticketArtifact = await artifacts.readArtifact('ITicket')
        ticket = await deployMockContract(wallet1, ticketArtifact.abi)

        const matchCardinality = 3
        
        await drawCalculator.initialize(ticket.address, matchCardinality, [ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")])

    })

    describe.only('calculate()', () => {
      it.only('should calculate and win grand prize', async () => {
        //function calculate(address user, uint256[] calldata randomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external override view returns (uint256){

        const winningNumber = utils.solidityKeccak256(["address"], [wallet1.address])//"0x1111111111111111111111111111111111111111111111111111111111111111"
        // console.log("winningNumber in test", winningNumber)
        const winningRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
        // console.log("winningRandomNumber in test", winningRandomNumber)

        const timestamp = 42
        const prizes = [utils.parseEther("100")]
        const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])

        await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([10]) // (user, timestamp): balance

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

        await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([10]) // (user, timestamp): balance

        expect(await drawCalculator.calculate(
            wallet1.address,
            [userRandomNumber],
            [timestamp],
            prizes,
            pickIndices
        )).to.equal(utils.parseEther("0"))
      })

      it('should calculate runner up prize', async () => {
        //function calculate(address user, uint256[] calldata winningRandomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data)

        const winningNumber = utils.solidityKeccak256(["address"], [wallet2.address])
        // console.log("winningNumber in test", winningNumber)
        const userRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
        console.log("userRandomNumber in test", userRandomNumber)

        const timestamp = 42
        const prizes = [utils.parseEther("100")]
        const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])

        await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([10]) // (user, timestamp): balance

        expect(await drawCalculator.calculate(
            wallet1.address,
            [userRandomNumber],
            [timestamp],
            prizes,
            pickIndices
        )).to.equal(utils.parseEther("20"))
      })
    });
})
