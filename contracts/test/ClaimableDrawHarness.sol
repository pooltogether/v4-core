// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../ClaimableDraw.sol";
import "../interfaces/IDrawCalculator.sol";

contract ClaimableDrawHarness is ClaimableDraw {
  
  // function createDraw(uint256 randomNumber, uint256 timestamp, uint256 prize) external override returns (uint256){
  //   return _createDraw(randomNumber, timestamp, prize);
  // } 

  // function claim(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes calldata data) external override {
  //   _claim(user, drawIds, drawCalculators, data);
  // }

  function readLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) external pure returns (bool) {
    return _readLastClaimFromClaimedHistory(_userClaimedDraws, _drawIndex);
  }

  function writeLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) external pure returns (bytes32) {
    return _writeLastClaimFromClaimedHistory(_userClaimedDraws, _drawIndex);
  }

}
