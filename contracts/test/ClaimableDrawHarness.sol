// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../ClaimableDraw.sol";
import "../interfaces/IDrawCalculator.sol";

contract ClaimableDrawHarness is ClaimableDraw {

  constructor(
    address _drawCalculatorManager,
    IDrawHistory _drawHistory
  ) ClaimableDraw(_drawCalculatorManager, _drawHistory) { }

  function __wrapCardinality(uint8 drawId) external pure returns (uint256) {
    return _wrapCardinality(drawId);
  }

  function __calculateDrawCollectionPayout(
    address _user,
    uint96[CARDINALITY] memory _userClaimedDraws,
    uint32[] calldata _drawIds,
    IDrawCalculator _drawCalculator,
    bytes calldata _data
  ) external returns (uint256 totalPayout, uint96[CARDINALITY] memory userClaimedDraws) {
    return _calculateDrawCollectionPayout(_user, _userClaimedDraws, _drawIds, _drawCalculator, _data);
  }

  function __updateUserDrawPayout(
    uint96[CARDINALITY] memory _userClaimedDraws,
    uint32 _drawId,
    uint96 _payout
  ) external view returns (uint96, uint96[CARDINALITY] memory) {
    return _updateUserDrawPayout(_userClaimedDraws, _drawId, _payout);
  }

  function __setUserDrawPayoutHistory(address user, uint96[CARDINALITY] memory _userClaimedDraws) external returns (bool) {
    _userDrawClaims[user] = _userClaimedDraws;
    return true;
  }

}
