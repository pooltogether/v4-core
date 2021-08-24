// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../ClaimableDraw.sol";
import "../interfaces/IDrawCalculator.sol";

contract ClaimableDrawHarness is ClaimableDraw {

  function createNewDraw(uint256 randomNumber, uint32 timestamp, uint256 prize) external returns (uint256) {
    return _createDraw(randomNumber, timestamp, prize);
  }

  function createNewDraws(uint256[] calldata randomNumbers, uint32[] calldata timestamps, uint256[] calldata prizes) external returns (uint256) {
    for (uint256 index = 0; index < randomNumbers.length; index++) {
      return _createDraw(randomNumbers[index], timestamps[index], prizes[index]);
    }
  }

  function drawIdToClaimIndex(uint256 drawId, uint256 _currentDrawId) external pure returns (uint256) {
    return _drawIdToClaimIndex(drawId, _currentDrawId);
  }

  function calculateDrawCollectionPayout(
    address _user,
    uint96[CARDINALITY] memory _userClaimedDraws,
    uint256[] calldata _drawIds,
    IDrawCalculator _drawCalculator,
    bytes calldata _data
  ) external returns (uint256 totalPayout, uint96[CARDINALITY] memory userClaimedDraws) {
    return _calculateDrawCollectionPayout(_user, _userClaimedDraws, _drawIds, _drawCalculator, _data);
  }

  function createDrawClaimsInput(
    uint256[] calldata _drawIds,
    IDrawCalculator _drawCalculator,
    uint256[] memory _randomNumbers,
    uint32[] memory _timestamps,
    uint256[] memory _prizes
  ) external view returns (uint256[] memory, uint32[] memory, uint256[] memory) {
    return _createDrawClaimsInput(_drawIds, _drawCalculator, _randomNumbers, _timestamps, _prizes);
  }

  function validateDrawPayout(
    uint96[CARDINALITY] memory _userClaimedDraws,
    uint256 _drawId,
    uint96 _payout
  ) external view returns (uint96, uint96[CARDINALITY] memory) {
    return _validateDrawPayout(_userClaimedDraws, _drawId, _payout);
  }

  function setUserDrawPayoutHistory(address user, uint96[CARDINALITY] memory userClaimedDraws, uint256 _nextDrawId) external returns (bool) {
    nextDrawId = _nextDrawId;
    userPayoutHistory[user] = userClaimedDraws;
    return true;
  }

  function transferERC20(IERC20Upgradeable _erc20Token, address _from, address _to, uint256 _amount) external returns (bool) {
    _transferERC20(_erc20Token, _from, _to, _amount);
  }

}
