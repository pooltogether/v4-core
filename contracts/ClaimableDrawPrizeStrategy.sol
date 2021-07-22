// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "hardhat/console.sol";
import "./ClaimableDraw.sol";
// import "@pooltogether/pooltogether-contracts/contracts/prize-strategy/PrizeSplit.sol";
// import "@pooltogether/pooltogether-contracts/contracts/prize-strategy/PeriodicPrizeStrategy.sol";


// contract ClaimableDrawPrizeStrategy is PeriodicPrizeStrategy, PrizeSplit, ClaimableDraw {

//   function _distribute (uint256 randomNumber) internal {
//     uint256 prize = prizePool.captureAwardBalance();
//     prize = _distributePrizeSplits(prize);

//     uint256 timestamp = block.timestamp;
//     _createDraw(randomNumber, timestamp, prize);
//   }

// }