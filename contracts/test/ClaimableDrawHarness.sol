// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../ClaimableDraw.sol";
import "../interfaces/IDrawCalculator.sol";

contract ClaimableDrawHarness is ClaimableDraw {
  
  function createNewDraw(uint256 randomNumber, uint32 timestamp, uint256 prize) external returns (uint256) {
    return _createDraw(randomNumber, timestamp, prize);
  } 

  // function readLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) external pure returns (bool) {
  //   return _readUsersDrawClaimStatusFromClaimedHistory(_userClaimedDraws, _drawIndex);
  // }

  // function writeLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) external pure returns (bytes32) {
  //   return _writeUsersDrawClaimStatusFromClaimedHistory(_userClaimedDraws, _drawIndex);
  // }
}
