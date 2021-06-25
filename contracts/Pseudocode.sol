// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;



contract PickHistory {

  // COMP token allows for users to opt-out of delegation for cheap transfers.

  function updateBalance(address user, uint256 balance, uint256 currentDrawNumber) external onlyPrizeStrategy {

    // get users current balance: (balance, draw number)

    // if currentDrawNumber > balance draw number
    //    then push new record onto stack (balance, currentDrawNumber) 20k gas
    // else
    //    update current record 5k gas

  }

  function setRandomNumber(bytes32 randomNumber, uint256 currentDrawNumber) external {

    // get users current random number: (random number, draw number)

    // if currentDrawNumber > random number draw number
    //    then push new record onto stack (random number, currentDrawNumber) 20k gas
    // else
    //    update current record 5k gas
  }

  function getBalance(address user, uint256 drawNumber) return (uint256) {

  }

  function getRandonNumber(address user, uint256 drawNumber) external view returns (bytes32) {
    // external call to prize strategy
  }

}




contract TsunamiPrizeStrategy {

  function setPendingWaveModel(address model) {
    // current model = pending model || last wave model in history
    // if model != current model
       // set pending model = model
  }

  function _distribute() {
    // record draw (bytes32 winningNumber, uint256 prize, uint256 totalDeposits)
    
    // if pending wave model
        // push onto wave model history (draw id, wave model address)
  }

  function claim(address user, draws[], pickIndices[][]) {
    // get draw (bytes32 winningNumber, uint256 prize, uint256 totalDeposits)
    // get users balance + random number for draw (balance, randomNumber)
    // get wave model for the draw

    prize = waveModel.calculate(winningNumber, prize, totalDeposits, balance, randomNumber)

    setClaimed(user, drawNumbers)

    award(user, prize)
  }
}


contract NumberMatchWaveModel {

  // immutable
  uint256 immutable PICK_COST = 10 ether;

  function calculateNumberOfPicks(balance) {
    return numberOfUserPicks = balance / PICK_COST;
  }

  function calculatePickAtIndex(randomNumber, index){ 
    return keccak(randomNumber + index);
  }

  function calculate(winningNumber, prize, totalDeposits, balance, randomNumber, pickIndices[]) view return (uint256) {
    // total picks = totalDeposits / PICK_COST

    // figure out right number of numbers
    // cast the winningNumber to the correct set of winning numbers

    numberOfUserPicks = balance / PICK_COST

    uint246 totalPrize

    for (each pick in picks) {
      pickNumber = keccak(keccak(randomNumber) + i))
      // format the pickNumber as the numbers
      // check match.

      require(pickNumber < numberOfUserPicks)

      matchCount = 0
      for (i = 0; i < 5; i++) {
        if (pickNumber[i] == winningNumber[i]) {
          matchCount++;
        }
      }

      if (matchCount == 1) {
        // award single match prize
        totalPrize += // their share of prize
      } else if (matchCount == 2) {
        // etc
      }

    }

    return totalPrize
  }

}