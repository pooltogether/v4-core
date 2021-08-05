import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet, BigNumber} from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Interface } from 'ethers/lib/utils';


const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;

type DrawSettings  = {
    matchCardinality: BigNumber
    pickCost: BigNumber
    distributions: BigNumber[]
    bitRangeValue: BigNumber
    bitRangeSize: BigNumber
}

describe('TsunamiDrawCalculator', () => {
    let drawCalculator: Contract; let ticket: MockContract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    const encoder = ethers.utils.defaultAbiCoder

    async function findWinningNumberForUser(userAddress: string, matchesRequired: number, drawSettings: DrawSettings) {
        console.log(`searching for ${matchesRequired} winning numbers for ${userAddress} with drawSettings ${JSON.stringify(drawSettings)}..`)
        const drawCalculator: Contract = await deployDrawCalculator(wallet1)
        
        let ticketArtifact = await artifacts.readArtifact('ITicket')
        ticket = await deployMockContract(wallet1, ticketArtifact.abi)
        
        await drawCalculator.initialize(ticket.address, drawSettings)
        
        const timestamp = 42
        const prizes = [utils.parseEther("1")]
        const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
        const ticketBalance = utils.parseEther("10")

        await ticket.mock.getBalances.withArgs(userAddress, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance

        const distributionIndex = drawSettings.matchCardinality.toNumber() - matchesRequired
        console.log("distributionIndex ", distributionIndex)

        if(drawSettings.distributions.length < distributionIndex){
           throw new Error(`There are only ${drawSettings.distributions.length} tiers of prizes`) // there is no "winning number" in this case
        }

        // now calculate the expected prize amount for these settings
        // totalPrize *  (distributions[index]/(range ^ index)) where index = matchCardinality - numberOfMatches
        const numberOfPrizes = Math.pow(drawSettings.bitRangeSize.toNumber(), distributionIndex)
        console.log("numberOfPrizes ", numberOfPrizes)
        
        const valueAtDistributionIndex : BigNumber = drawSettings.distributions[distributionIndex]
        console.log("valueAtDistributionIndex ", valueAtDistributionIndex)
        const percentageOfPrize: BigNumber= valueAtDistributionIndex.div(numberOfPrizes)
        const expectedPrizeAmount : BigNumber = (prizes[0]).mul(percentageOfPrize as any).div(ethers.constants.WeiPerEther) 

        console.log("expectedPrizeAmount ", expectedPrizeAmount.toString())
        let winningRandomNumber

        while(true){
            winningRandomNumber = utils.solidityKeccak256(["address"], [ethers.Wallet.createRandom().address])
            console.log("trying a new random number")
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
        drawCalculator = await deployDrawCalculator(wallet1)

        let ticketArtifact = await artifacts.readArtifact('ITicket')
        ticket = await deployMockContract(wallet1, ticketArtifact.abi)

        const drawSettings : DrawSettings = {
            distributions: [ethers.utils.parseEther("0.8"), ethers.utils.parseEther("0.2")],
            pickCost: BigNumber.from(utils.parseEther("1")),
            matchCardinality: BigNumber.from(5),
            bitRangeValue: BigNumber.from(15),
            bitRangeSize : BigNumber.from(4)
        }
        
        await drawCalculator.initialize(ticket.address, drawSettings)
    })

    describe('finding winning random numbers with helper', ()=>{
        it('find 3 winning numbers', async ()=>{
            const params: DrawSettings = {
                matchCardinality: BigNumber.from(5),
                distributions: [ethers.utils.parseEther("0.6"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(7),
                bitRangeSize : BigNumber.from(3)
            }
            const result = await findWinningNumberForUser(wallet1.address, 3, params)
        })
    })

    describe('admin functions', ()=>{
        it('onlyOwner can setPrizeSettings', async ()=>{
            const params: DrawSettings = {
                matchCardinality: BigNumber.from(5),
                distributions: [ethers.utils.parseEther("0.6"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],      
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(15),
                bitRangeSize : BigNumber.from(4)
            }

            expect(await drawCalculator.setDrawSettings(params)).
                to.emit(drawCalculator, "DrawSettingsSet")

            await expect(drawCalculator.connect(wallet2).setDrawSettings(params)).to.be.reverted
        })

        it('cannot set over 100pc of prize for distribution', async ()=>{
            const params: DrawSettings = {
                matchCardinality: BigNumber.from(5),
                distributions: [ethers.utils.parseEther("0.9"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(15),
                bitRangeSize : BigNumber.from(4)
            }
            await expect(drawCalculator.setDrawSettings(params)).
                to.be.revertedWith("DrawCalc/distributions-gt-100%")
        })
        
        it('cannot set range over 15', async ()=>{
            const params: DrawSettings = {
                matchCardinality: BigNumber.from(5),
                distributions: [ethers.utils.parseEther("0.9"),
                                ethers.utils.parseEther("0.1"),
                            ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(15),
                bitRangeSize : BigNumber.from(1)
            }
            await expect(drawCalculator.setDrawSettings(params)).
                to.be.revertedWith("DrawCalc/bitRangeValue-incorrect")
        })
    })

    describe('findBitMatchesAtIndex()', ()=>{
        //function findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 indexOffset, uint8 _bitRangeSize, uint8 _maskValue) external returns(bool) 
        it('should match the value at 0 index over 4 bits', async ()=>{
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("63","63","0", "4","15")
            expect(result).to.equal(true)
        })
        it('should not match the value at 0 index over 8 bits', async ()=>{
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("64","63","0","8", "255")
            expect(result).to.equal(false)
        })

        it('should match the value at 0 index over 7 bits', async ()=>{
            //63: 0 1111 11
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("63","63","0","7", "127")
            expect(result).to.equal(true)
        })

        it('should match the value at 1 index over 4 bits', async ()=>{
            // 252: 1111 1100
            // 255  1111 1111
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("252","255","1","4","15")
            expect(result).to.equal(true)
        })
        it('should NOT match the value at 0 index over 4 bits', async ()=>{
            // 252: 1111 1100
            // 255  1111 1111
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("252","255","0","4","15")
            expect(result).to.equal(false)
        })
        it('should match the value at 1 index over 2 bits', async ()=>{
            // 252: 1111 11 00
            // 255  1111 11 11
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("252","255","1","2","3")
            expect(result).to.equal(true)
        })

        it('should match the value at 0 index over 6 bits', async ()=>{
            // 61676: 001111 000011 101100
            // 61612: 001111 000010 101100
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("61676","61612","0","6","63")
            expect(result).to.equal(true)
        })

        it('should NOT match the value at 1 index over 6 bits', async ()=>{
            // 61676: 001111 000011 101100
            // 61612: 001111 000010 101100
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("61676","61612","1","6","63")
            expect(result).to.equal(false)
        })

        it('should match the value at 2 index over 6 bits', async ()=>{
            // 61676: 001111 000011 101100
            // 61612: 001111 000010 101100
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("61676","61612","2","6","63")
            expect(result).to.equal(true)
        })

        it('should NOT match the value at 0 index over 8 bits', async ()=>{
            // 61676: 11110000 11101100
            // 61612: 11110000 10101100
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("61676","61612","0","8","255")
            expect(result).to.equal(false)
        })

        it('should match the value at 1 index over 8 bits', async ()=>{
            // 61676: 11110000 11101100
            // 61612: 11110000 10101100
            const result = await drawCalculator.callStatic.findBitMatchesAtIndex("61676","61612","1","8","255")
            expect(result).to.equal(true)
        })
    })

    describe('calculate()', () => {
        it('should calculate and win grand prize', async () => {
            const winningNumber = utils.solidityKeccak256(["address"], [wallet1.address])
            const winningRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
        
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

        it('should not have enough funds for a second pick and revert', async () => {
            const winningNumber = utils.solidityKeccak256(["address"], [wallet1.address])
            const winningRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
            
            const timestamp1 = 42
            const timestamp2 = 51
            const prizes = [utils.parseEther("100"), utils.parseEther("20")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"],["2"]]])
            const ticketBalance = utils.parseEther("10")
            const ticketBalance2 = utils.parseEther("0.4")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp1,timestamp2]).returns([ticketBalance, ticketBalance2]) // (user, timestamp): balance

            await expect(drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber, winningRandomNumber],
                [timestamp1, timestamp2],
                prizes,
                pickIndices
            )).to.revertedWith("DrawCalc/insufficient-user-picks")
        
        })

        it('should calculate and win nothing', async () => {
            
            const winningNumber = utils.solidityKeccak256(["address"], [wallet2.address])
            const userRandomNumber = utils.solidityKeccak256(["bytes32", "uint256"],[winningNumber, 1])
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
            
            const timestamp = 42
            const prizes = [utils.parseEther("100")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
            const ticketBalance = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance
            
            let params: DrawSettings = {
                matchCardinality: BigNumber.from(6),
                distributions: [ethers.utils.parseEther("0.2"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(15),
                bitRangeSize : BigNumber.from(4)
            }
            await drawCalculator.setDrawSettings(params)

            let winningRandomNumber = await findWinningNumberForUser(wallet1.address, 3, params)
            const resultingPrize = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize).to.equal(ethers.BigNumber.from(utils.parseEther("0.15625")))
            // now increase cardinality 
            params = {
                matchCardinality: BigNumber.from(7),
                distributions: [ethers.utils.parseEther("0.2"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(15),
                bitRangeSize : BigNumber.from(4)
            }
            await drawCalculator.setDrawSettings(params)
            winningRandomNumber = await findWinningNumberForUser(wallet1.address, 3, params)
            const resultingPrize2 = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize2).to.equal(ethers.BigNumber.from(utils.parseEther("0.0390625")))
        })

        it('increasing the number range results in lower probability of matches', async () => {
            
            //function calculate(address user, uint256[] calldata winningRandomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data)
            const timestamp = 42
            const prizes = [utils.parseEther("100")]
            const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
            const ticketBalance = utils.parseEther("10")

            await ticket.mock.getBalances.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]) // (user, timestamp): balance
        
            let params: DrawSettings = {
                matchCardinality: BigNumber.from(5),
                distributions: [ethers.utils.parseEther("0.2"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(7),
                bitRangeSize : BigNumber.from(3)
            }
            await drawCalculator.setDrawSettings(params)

            const winningRandomNumber = await findWinningNumberForUser(wallet1.address, 3, params)
            
            const resultingPrize = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize).to.equal(ethers.BigNumber.from(utils.parseEther("1.1111111111111111")))
            // now increase number range 
            params = {
                matchCardinality: BigNumber.from(5),
                distributions: [ethers.utils.parseEther("0.2"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1"),
                            ethers.utils.parseEther("0.1")
                        ],
                pickCost: BigNumber.from(utils.parseEther("1")),
                bitRangeValue: BigNumber.from(15),
                bitRangeSize : BigNumber.from(4)
            }
            await drawCalculator.setDrawSettings(params)

            const winningRandomNumber2 = await findWinningNumberForUser(wallet1.address, 3, params)

            const resultingPrize2 = await drawCalculator.calculate(
                wallet1.address,
                [winningRandomNumber2],
                [timestamp],
                prizes,
                pickIndices
            )
            expect(resultingPrize2).to.equal(ethers.BigNumber.from(utils.parseEther("0.625")))
        })


    });
})