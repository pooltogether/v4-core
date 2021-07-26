type Distributions = {
    values : number[]
}

async function runSimulation(matchCardinality: number, distributions:Distributions, range: number, userAddress: string, winningRandomNumber: string) {
    console.log("running sim")
    const distributionsLength = distributions.values.length
    if(matchCardinality > distributionsLength){
        throw new Error("matchCardinality too great")//require(_distributions.length <= matchCardinality, "distributions gt cardinality");
    }

    // for index < matchCardinality
    
     // getValueAtIndex()



}

function getValueAtIndex(word: string, index: number, _range: number){
    // how to elinimate modulo boas here
}



// TOP DOWN APPROACH 
//for fixed number of tries i.e 1,000

    // generate winning random number using createRandomWallet

    // runSimulation() and record number of runs for it to return 

    // matchCardinality++


/*

    represent binary thru strings or ?

    // BOTTOM UP

    // or calculate the probability that 4 bits will match
    // probability 1 bit from 4 will match = 1 / 2 bits ^ (1) = 0.5
    // probability 2 bits will match = 1 / 2 bits ^ (2) = 0.25
    // probability 3 bits will match = 1 / 2 bits ^ (3) = 1/8
    // probability 4 bits will match = 1 / 2 bits ^ (4) = 1/16
    // etc. 

    


*/