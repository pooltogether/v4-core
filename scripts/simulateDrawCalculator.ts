import { BigNumber, ethers } from "ethers";
import {Draw, DrawSettings, User} from "./types"



export function runDrawCalculatorForSingleDraw(drawSettings: DrawSettings, draw: Draw, user: User): BigNumber { // returns number of runs it took to find a result
    console.log("running single draw calc")
    
    const sanityCheckDrawSettingsResult = sanityCheckDrawSettings(drawSettings)
    
    if(sanityCheckDrawSettingsResult != ""){
        throw new Error(`DrawSettings invalid: ${sanityCheckDrawSettingsResult}`)
    }

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
    return pickPayoutFraction.mul(draw.prize);
}

//function calculatePickFraction(uint256 randomNumberThisPick, uint256 winningRandomNumber, DrawSettings memory _drawSettings)
export function calculatePickFraction(randomNumberThisPick: string, winningRandomNumber: BigNumber, _drawSettings: DrawSettings, draw: Draw): BigNumber {
    
    const prizeFraction : BigNumber = BigNumber.from(0);
    let numberOfMatches : number = 0;

    // for(uint256 matchIndex = 0; matchIndex < _matchCardinality; matchIndex++){
    for(let matchIndex = 0; matchIndex < _drawSettings.matchCardinality.toNumber(); matchIndex++){
        const _matchIndexOffset: number = matchIndex - _drawSettings.bitRangeSize.toNumber()

        if(findBitMatchesAtIndex(BigNumber.from(randomNumberThisPick), winningRandomNumber, BigNumber.from(_matchIndexOffset), _drawSettings.bitRangeValue)){
            numberOfMatches++;
        }
    }
    console.log(`found ${numberOfMatches} matches..`)

    return calculatePrizeAmount(_drawSettings, draw, numberOfMatches)
}


//function _findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 indexOffset, uint8 _bitRangeMaskValue) 
export function findBitMatchesAtIndex(word1: BigNumber, word2: BigNumber, indexOffset: BigNumber, bitRangeValue: BigNumber): boolean {

    const word1DataHexString: string = word1.toHexString()
    const word2DataHexString: string = word2.toHexString()

    //https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/BigInt#operators

    const mask : BigInt = BigInt(bitRangeValue.toString()) << BigInt(indexOffset.toString())

    const bits1 = BigInt(word1DataHexString) & BigInt(mask)
    const bits2 = BigInt(word2DataHexString) & BigInt(mask)

    return bits1 == bits2
}


// calculates the absolute amount of Prize in Wei for the Draw and DrawSettings
export function calculatePrizeAmount(drawSettings: DrawSettings, draw: Draw, matches :number): BigNumber {
    const distributionIndex = drawSettings.matchCardinality.toNumber() - matches
    console.log("distributionIndex ", distributionIndex)

    if(distributionIndex > drawSettings.distributions.length){
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



export function sanityCheckDrawSettings(drawSettings: DrawSettings) : string {

    if(drawSettings.matchCardinality.gt(drawSettings.distributions.length)){
        console.log("DrawCalc/matchCardinality-gt-distributions")
        return "DrawCalc/matchCardinality-gt-distributions"
    }
    else if(!(drawSettings.bitRangeValue.toNumber() == (Math.pow(2, drawSettings.bitRangeSize.toNumber())-1))){
        return "DrawCalc/bitRangeValue-incorrect"
    }
    else if(drawSettings.bitRangeSize.gte(Math.floor((256 / drawSettings.matchCardinality.toNumber())))){
        return "DrawCalc/bitRangeSize-too-large"
    }
    else if(drawSettings.pickCost.lte(0)){
        return "DrawCalc/pick-gt-0"
    }
    else{
        let sum = BigNumber.from(0)
        for(let i = 0; i < drawSettings.distributions.length; i++){
            sum = sum.add(drawSettings.distributions[i])
        }
        if(sum.gte(ethers.utils.parseEther("1"))){
            return "DrawCalc/distributions-gt-100%"
        }
    }
    return ""
}