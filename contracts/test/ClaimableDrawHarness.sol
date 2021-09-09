// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../ClaimableDraw.sol";
import "../interfaces/IDrawCalculator.sol";

contract ClaimableDrawHarness is ClaimableDraw {
  
  function drawIdToClaimIndex(uint8 drawId) external pure returns (uint256) {
    return _drawIdToClaimIndex(drawId);
  } 

  function calculateDrawCollectionPayout(
    address _user,
    uint96[PAYOUT_CARDINALITY] memory _userClaimedDraws, 
    uint32[] calldata _drawIds, 
    IDrawCalculator _drawCalculator, 
    bytes calldata _data
  ) external returns (uint256 totalPayout, uint96[PAYOUT_CARDINALITY] memory userClaimedDraws) {
    return _calculateDrawCollectionPayout(_user, _userClaimedDraws, _drawIds, _drawCalculator, _data);
  } 


  function validateDrawPayout(
    uint96[PAYOUT_CARDINALITY] memory _userClaimedDraws, 
    uint32 _drawId, 
    uint96 _payout
  ) external view returns (uint96, uint96[PAYOUT_CARDINALITY] memory) {
    return _validateDrawPayout(_userClaimedDraws, _drawId, _payout);
  } 

  function setUserDrawPayoutHistory(address user, uint96[PAYOUT_CARDINALITY] memory userClaimedDraws) external returns (bool) {
    userPayoutHistory[user] = userClaimedDraws;
    return true;
  } 

}
