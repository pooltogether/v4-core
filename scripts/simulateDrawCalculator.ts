import { BigNumber, ethers } from "ethers";

type DrawSettings  = {
    matchCardinality: BigNumber
    pickCost: BigNumber
    distributions: BigNumber[]
    bitRangeValue: BigNumber
    bitRangeSize: BigNumber
}

type Draw = {
    timestamp : number // dont think this is needed
    prize: BigNumber
    winningRandomNumber: BigNumber
}

type User = {
    address: string
    balance: BigNumber
    pickIndices: BigNumber[]
}


const exampleDrawSettings : DrawSettings = {
    distributions: [ethers.utils.parseEther("0.3"),
                    ethers.utils.parseEther("0.2"),
                    ethers.utils.parseEther("0.1")],
    pickCost: BigNumber.from(ethers.utils.parseEther("1")),
    matchCardinality: BigNumber.from(5),
    bitRangeValue: BigNumber.from(15),
    bitRangeSize : BigNumber.from(4)
}

const exampleDraw : Draw = {
    timestamp : 10000,
    prize: BigNumber.from(100),
    winningRandomNumber: BigNumber.from(61676)
}

const exampleUser : User = {
    address: "0x568Ea56Dd5d8044269b1482D3ad4120a7aB0933A",
    balance: ethers.utils.parseEther("10"),
    pickIndices: [BigNumber.from(1)]
} 



runDrawCalculatorForSingleDraw(exampleDrawSettings, exampleDraw, exampleUser)

async function runSimulationNTimes(n: number, drawSettings: DrawSettings){
    console.log(`running DrawCalculator simulation ${n} times..`)

    //record starting time

    // for i = 0; i < n; 
        // change random number
        // runDrawCalculatorForSingleWinningNumber

    //record finishing time
}

async function runDrawCalculatorForSingleDraw(drawSettings: DrawSettings, draw: Draw, user: User): Promise<BigNumber>{ // returns number of runs it took to find a result
    console.log("running single draw calc")
    /* CALCULATE() */
    //  bytes32 userRandomNumber = keccak256(abi.encodePacked(user)); // hash the users address
    const userRandomNumber = ethers.utils.solidityKeccak256(["address"], [user.address])
    console.log("user random number ")
    // for (uint256 index = 0; index < winningRandomNumbers.length; index++) {

    //single winning number -> no loop required

    /* _CALCULATE()*/   
    // uint256 totalUserPicks = balance / _drawSettings.pickCost;
    const totalUserPicks = user.balance.div(drawSettings.pickCost)
    console.log("totalUserPicks ", totalUserPicks)
    let pickPayoutFraction: BigNumber = BigNumber.from(0)

    const defaultAbiCoder = ethers.utils.defaultAbiCoder

    const picksLength = user.pickIndices.length
    //for(uint256 index  = 0; index < picks.length; index++){
    for(let i =0; i < picksLength; i++){
        if(user.pickIndices[i] > totalUserPicks){
            throw new Error(`User does not have this many picks!`)
        }
    
        // uint256 randomNumberThisPick = uint256(keccak256(abi.encode(userRandomNumber, picks[index])));       
        const abiEncodedRandomNumberPlusPickIndice = defaultAbiCoder.encode(["bytes32","uint256"],[userRandomNumber,user. pickIndices[i]])
        console.log(abiEncodedRandomNumberPlusPickIndice)
        
        // does the below line type need to be bytes32?
        const randomNumberThisPick: string = ethers.utils.solidityKeccak256(["string"], [abiEncodedRandomNumberPlusPickIndice])
        
        // pickPayoutFraction += calculatePickFraction(randomNumberThisPick, winningRandomNumber, _drawSettings);
        pickPayoutFraction = pickPayoutFraction.add(calculatePickFraction(randomNumberThisPick, draw.winningRandomNumber, drawSettings, draw))

    }
    return pickPayoutFraction.mul(draw.prize); // div by 1 ether? 
}

//function calculatePickFraction(uint256 randomNumberThisPick, uint256 winningRandomNumber, DrawSettings memory _drawSettings)
function calculatePickFraction(randomNumberThisPick: string, winningRandomNumber: BigNumber, _drawSettings: DrawSettings, draw: Draw):BigNumber{
    
    const prizeFraction : BigNumber = BigNumber.from(0);
    let numberOfMatches : number = 0;

    // for(uint256 matchIndex = 0; matchIndex < _matchCardinality; matchIndex++){
    for(let matchIndex = 0; matchIndex < _drawSettings.matchCardinality.toNumber(); matchIndex++){
        const _matchIndexOffset: number = matchIndex - _drawSettings.bitRangeSize.toNumber()

        if(findBitMatchesAtIndex(BigNumber.from(randomNumberThisPick), winningRandomNumber, BigNumber.from(_matchIndexOffset), _drawSettings.bitRangeValue)){
            numberOfMatches++;
        }
    }
    console.log(`found ${numberOfMatches}`)

    return calculatePrizeAmount(_drawSettings, draw, numberOfMatches)

}


//function _findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 indexOffset, uint8 _bitRangeMaskValue) 
function findBitMatchesAtIndex(word1: BigNumber, word2: BigNumber, indexOffset: BigNumber, bitRangeValue: BigNumber): boolean {

    const word1DataHexString: string = word1.toHexString()
    const word2DataHexString: string = word2.toHexString()

    //https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/BigInt#operators

    // const word1BigInt : BigInt = BigInt(word1DataHexString)
    // const word2BigInt : BigInt = BigInt(word2DataHexString)

    const mask : BigInt = BigInt(bitRangeValue.toString()) << BigInt(indexOffset.toString())

    const bits1 = BigInt(word1DataHexString) & BigInt(mask) // need to re-cast here stop compiler from complaining
    const bits2 = BigInt(word2DataHexString) & BigInt(mask)

    return bits1 == bits2

}

// console.log(findBitMatchesAtIndex(BigNumber.from(61676),
//                                  BigNumber.from(61612),
//                                  BigNumber.from(8),
//                                   BigNumber.from(255)))


// calculates the absolute amount of Prize in Wei for the Draw and DrawSettings
function calculatePrizeAmount(drawSettings: DrawSettings, draw: Draw, matches :number): BigNumber {
    const distributionIndex = drawSettings.matchCardinality.toNumber() - matches
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
    const expectedPrizeAmount : BigNumber = (draw.prize).mul(percentageOfPrize).div(ethers.constants.WeiPerEther) 

    console.log("expectedPrizeAmount ", expectedPrizeAmount.toString())

    return expectedPrizeAmount
}

