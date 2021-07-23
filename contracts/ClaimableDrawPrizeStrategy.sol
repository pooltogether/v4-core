// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "hardhat/console.sol";

import "./ClaimableDraw.sol";
import "./import/prize-strategy/PrizeSplit.sol";
import "./import/prize-strategy/PeriodicPrizeStrategy.sol";

contract ClaimableDrawPrizeStrategy is PeriodicPrizeStrategy, PrizeSplit, ClaimableDraw {

  function _distribute (uint256 randomNumber) internal override {
    uint256 prize = prizePool.captureAwardBalance();
    prize = _distributePrizeSplits(prize);

    uint256 timestamp = block.timestamp;
    _createDraw(randomNumber, timestamp, prize);
  }

  function _awardPrizeSplitAmount(address target, uint256 amount, uint8 tokenIndex) internal override {

  }

}