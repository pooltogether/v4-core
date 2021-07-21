// // SPDX-License-Identifier: MIT
// pragma solidity >=0.6.0 <0.8.0;



// contract Ticket {

//   // COMP token allows for users to opt-out of delegation for cheap transfers.
//   struct Balance {
//     uint224 balance;
//     uint32 twabIndex;
//   }

//   mapping(address => Balance) balances;

//   struct RingBuffer {
//     Twab[65535] balances;
//   }

//   mapping(address => RingBuffer) twabs;

//   function _beforeTokenTransfer() {
//     // update TWAB
//     twabs[msg.sender].balances[ balances[msg.sender].twabIndex ] = // add to last one
//     balances[msg.sender].twabIndex++;
//   }

//   function claim(address claimable, uint256[] timestamps, bytes data) {
//     uint256[] balances = figureOutBalances(timestamps)
//     IClaimable(claimable).claim(msg.sender, timestamps, balances, data)
//   }

// }


// interface IClaimable {
//   function claim(address sender, uint256[] timestamps, uint256[] balances, uint256[][] picks);
// }

// contract TsunamiPrizeStrategy is IClaimable {

//   struct WaveModelSet {
//     uint32 timestamp;
//     IWaveModel waveModel;
//   }

//   WaveModelSet[] waveModelSets;

//   function setPendingWaveModel(IWaveModel model) {
//     waveModelSets.push(WaveModelSet(block.timestamp, model))
//   }

//   function completeAward() {
//     prize = captureAwardBalance()
//     // record draw (bytes32 winningNumber, uint256 prize, uint256 ticketTotalSupply, uint256 drawNumber)
//   }

//   // draw 1: time(0), balance(100), 10 picks.  2, 7 won.  The user then submits pick 2 and 7

//   function claim(address sender, uint256[] timestamps, uint256[] balances, uint256[][] picks) {
//     // get draw (bytes32 winningNumber, uint256 prize, uint256 ticketTotalSupply)
//     // get users balance + random number for draw (balance, randomNumber)
//     // get wave model for the draw

//     uint256[][] picks = abi.decode(data);

//     uint256 completeDraws;

//     uint256 prize = 0;
//     foreach( timestamps ) {
//       draw = findDraw(timestamp)
//       randomNumber = hash(sender)
//       prize += waveModel.calculate(draw.winningNumber, draw.prize, draw.ticketTotalSupply, balance, randomNumber, picksForThetimestamp)
//       // flip the right bit on completeDraws to 1
//     }

//     draws = draws | completeDraws

//     setClaimed(user, timestamps)

//     prizePool.awardTickets(user, prize)
//   }
// }

// interface IWaveModel {
//   function calculate(winningNumber, prize, ticketTotalSupply, balance, randomNumber, pickIndices[]) view return (uint256);
// }

// contract NumberMatchWaveModel {

//   // immutable
//   uint256 immutable PICK_COST = 10 ether;

//   function calculateNumberOfPicks(balance) {
//     return numberOfUserPicks = balance / PICK_COST;
//   }

//   function calculatePickAtIndex(randomNumber, index){ 
//     return keccak(randomNumber + index);
//   }

//   function calculate(winningNumber, prize, ticketTotalSupply, balance, randomNumber, pickIndices[]) view return (uint256) {
//     // total picks = ticketTotalSupply / PICK_COST

//     // figure out right number of numbers
//     // cast the winningNumber to the correct set of winning numbers

//     numberOfUserPicks = balance / PICK_COST

//     uint246 totalPrize

//     requiredMatches = // figure out right magnitude of matches

//     for (each pick in picks) {
//       require(pickNumber < numberOfUserPicks)

//       pickNumber = keccak(randomNumber) + i)
//       // format the pickNumber as the numbers
//       // check match.


//       matchCount = 0
//       for (i = 0; i < requiredMatches; i++) {
//         if (pickNumber[i] == winningNumber[i]) {
//           matchCount++;
//         }
//       }

//       if (matchCount == 1) {
//         // award single match prize
//         totalPrize += // their share of prize
//       } else if (matchCount == 2) {
//         // etc
//       }

//     }

//     return totalPrize
//   }

// }