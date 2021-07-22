// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../ClaimableDraw.sol";
import "../interfaces/IDrawCalculator.sol";

contract ClaimableDrawHarness is ClaimableDraw {
  
  function createDraw(uint256 randomNumber, uint256 timestamp, uint256 prize) external returns (uint256){
    return _createDraw(randomNumber, timestamp, prize);
  } 

  function claimIt(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes calldata data) external {
    _claim(user, drawIds, drawCalculators, data);
  }

}
