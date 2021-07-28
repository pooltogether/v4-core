import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet, BigNumber} from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Interface } from 'ethers/lib/utils';
import { timeStamp } from 'console';

const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;


type PrizeDistribution = {
    values: BigNumber[]
}
type DrawParams = {
    matchCardinality: number
    numberRange: number
    distribution: PrizeDistribution
}


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

describe.only('TsunamiDrawCalculator', () => {
    let drawCalculator: Contract; let ticket: MockContract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    
    let draw: any
    const encoder = ethers.utils.defaultAbiCoder



    async function findWinningNumberForUser(userAddress: string, matchesRequired: number, drawParams: DrawParams) {
        console.log(`searching for ${matchesRequired} winning numbers for ${userAddress}..`)
        const drawCalculator: Contract = await deployDrawCalculator(wallet1)
        
        let ticketArtifact = await artifacts.readArtifact('ITicket')
        ticket = await deployMockContract(wallet1, ticketArtifact.abi)

        await drawCalculator.initialize(ticket.address, drawParams.matchCardinality, drawParams.distribution.values, drawParams.numberRange)

        const timestamp = 42
        const prizes = [utils.parseEther("1")]
        const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
        const ticketBalance = utils.parseEther("10")

        await ticket.mock.getBalances.withArgs(userAddress, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance

        const distributionIndex = drawParams.matchCardinality - matchesRequired
        if(distributionIndex > drawParams.distribution.values.length){
            console.log(`There are ${drawParams.distribution.values.length} tiers of prizes`)
            return
        }

        console.log("distributionIndex ", distributionIndex)
        const numberOfPrizes = Math.pow(drawParams.numberRange,distributionIndex)
        console.log("number of prizes with these params ", numberOfPrizes)
        const valueAtDistributionIndex : BigNumber = drawParams.distribution.values[distributionIndex]
        console.log("valueAtDistributionIndex", valueAtDistributionIndex)
        
        const percentageOfPrize: BigNumber= valueAtDistributionIndex.div(numberOfPrizes)
        console.log("percentage of prize ", percentageOfPrize.toString())

        const expectedPrizeAmount : BigNumber = (prizes[0]).mul(percentageOfPrize as any).div(ethers.constants.WeiPerEther) // totalPrize *  (distributions[index]/(range ^ index)) where index = matchCardinality - numberOfMatches

        console.log("expectedPrizeAmount ", expectedPrizeAmount.toString())

        let winningRandomNumber

        while(true){
            winningRandomNumber = utils.solidityKeccak256(["address"], [ethers.Wallet.createRandom().address])

            const result = await drawCalculator.calculate(
                userAddress,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )

            if(result.eq(expectedPrizeAmount)){
                console.log("found a winning number!", winningRandomNumber)
                break
            }
        }
    
        return winningRandomNumber
    }

    async function deployDrawCalculator(signer: any): Promise<Contract>{
        const drawCalculatorFactory = await ethers.getContractFactory("TsunamiDrawCalculatorHarness", signer)
        const drawCalculator:Contract = await drawCalculatorFactory.deploy()
        return drawCalculator
    }

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

    describe('finding winning random numbers with helper', ()=>{
        it('find 3 winning numbers', async ()=>{
            const params: DrawParams = {
                matchCardinality: 5,
                distribution: {
                    values:[ethers.utils.parseEther("0.6"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ]
                },
                numberRange: 5
            }
            const result = await findWinningNumberForUser(wallet1.address, 3, params)
        })
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
                to.emit(drawCalculator, "NumberRangeSet").
                withArgs(5)
            await expect(drawCalculator.connect(wallet2).setNumberRange(5)).to.be.reverted
        })
        
        it('onlyOwner set prize distributions', async ()=>{
            expect(await drawCalculator.setPrizeDistribution([ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")])).
                to.emit(drawCalculator, "PrizeDistributionsSet")
            await expect(drawCalculator.connect(wallet2).setPrizeDistribution(
                [ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")])).
                to.be.reverted
        })

        it('cannot set over 100pc of prize for distribution', async ()=>{
            await expect(drawCalculator.setPrizeDistribution([ethers.utils.parseEther("0.9"), ethers.utils.parseEther("0.2")])).
                to.be.revertedWith("sum of distributions too large")
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

        it('should calculate for multiple picks, first pick grand prize winner, second pick no winnings', async () => {
            //function calculate(address user, uint256[] calldata randomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external override view returns (uint256){

            const winningNumber = utils.solidityKeccak256(["address"], [wallet1.address])
            const winningRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
            
            const timestamp1 = 42
            const timestamp2 = 51
            const prizes = [utils.parseEther("100"), utils.parseEther("20")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"],["2"]]])
            const ticketBalance = utils.parseEther("10")
            const ticketBalance2 = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp1,timestamp2]).returns([ticketBalance, ticketBalance2]) // (user, timestamp): balance

            expect(await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber, winningRandomNumber],
                [timestamp1, timestamp2],
                prizes,
                pickIndices
            )).to.equal(utils.parseEther("80"))
        
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

        it('increasing the number range results in lower probability of matches', async () => {
            
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

            const params: DrawParams = {
                matchCardinality: 5,
                distribution: {
                    values:[
                            ethers.utils.parseEther("0.2"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ]
                },
                numberRange: 4
            }
            const winningRandomNumber = await findWinningNumberForUser(wallet1.address, 3, params)
            
            const resultingPrize = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize).to.equal(ethers.BigNumber.from(utils.parseEther("0.625"))) // with 3 matches

            // now increase number range 
            await drawCalculator.setNumberRange(6) // this means from 0 to 6 is available for matching
      
            const params2: DrawParams = {
                matchCardinality: 5,
                distribution: {
                    values:[ethers.utils.parseEther("0.2"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ]
                },
                numberRange: 6
            }
            const winningRandomNumber2 = await findWinningNumberForUser(wallet1.address, 3, params2)

            const resultingPrize2 = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber2],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize2).to.equal(ethers.BigNumber.from(utils.parseEther("0.2777777777777777")))
        })


    });
})
