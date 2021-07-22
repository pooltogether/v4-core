// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";

import "./interfaces/IDrawCalculator.sol";

abstract contract ClaimableDraw {
  uint256 currentDrawId;
  uint256 currentDrawIndex;
  Draw[] internal draws;

  mapping(address => bytes32) internal claimedDraws;

  IDrawCalculator internal currentCalculator;

  struct Draw {
    uint256 randomNumber;
    uint256 timestamp;
    uint256 prize;
    IDrawCalculator calculator;
  }

  event Claimed (
    address indexed user,
    bytes32 userClaimedDraws,
    uint256 prize
  );

  event CalculatorSet (
    IDrawCalculator indexed calculator
  );

  function setDrawCalculator(IDrawCalculator calculator) external {
    currentCalculator = calculator;
    emit CalculatorSet(calculator);
  }

  function hasClaimed(address user, uint256 drawId) external view returns (bool) {
    uint8  drawIndex  = _drawIdToClaimIndex(drawId, currentDrawIndex);
    bytes32 userClaimedDraws = claimedDraws[user]; //sload
    return _readLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);
  }


  function _claim(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes calldata data) internal returns (uint256){
    require(drawCalculators.length == drawIds.length, "length-mismatch");
    bytes32 userClaimedDraws = claimedDraws[user]; //sload
    uint256 _currentDrawId = currentDrawId; // sload

    uint256 totalPayout;
    for (uint256 calcIndex = 0; calcIndex < drawCalculators.length; calcIndex++) {
      uint256 payout;
      IDrawCalculator _drawCalculator = drawCalculators[calcIndex];
    
      (payout, userClaimedDraws) = _calculateAllDraws(user, drawIds[calcIndex], _drawCalculator, data, _currentDrawId, userClaimedDraws);
      totalPayout = totalPayout + payout;
    }

    claimedDraws[user] = userClaimedDraws; //sstore

    return totalPayout;
  }

  function _calculateAllDraws(address user, uint256[] calldata drawIds, IDrawCalculator drawCalculator, bytes calldata data, uint256 _currentDrawId, bytes32 _claimedDraws) internal returns (uint256 totalPayout, bytes32 userClaimedDraws) {
    uint256[] memory prizes = new uint256[](drawIds.length);
    uint256[] memory timestamps = new uint256[](drawIds.length);
    uint256[] memory randomNumbers = new uint256[](drawIds.length);

    for (uint256 drawIndex = 0; drawIndex < drawIds.length; drawIndex++) {
      Draw memory _draw = draws[drawIds[drawIndex]];
      require(_draw.calculator == drawCalculator, "calculator-address-invalid");

      prizes[drawIndex] = _draw.prize;
      timestamps[drawIndex] = _draw.timestamp;
      randomNumbers[drawIndex] = _draw.randomNumber;
      
      userClaimedDraws = _claimDraw(_claimedDraws, drawIds[drawIndex], _currentDrawId);
    }

    totalPayout += drawCalculator.calculate(user, randomNumbers, timestamps, prizes, data);
  }

  function _createDraw(uint256 randomNumber, uint256 timestamp, uint256 prize) internal returns (uint256){
    Draw memory _draw = Draw(randomNumber, timestamp,prize, currentCalculator);
    currentDrawId = draws.length;
    draws.push(_draw);
    return currentDrawId;
  } 

  // function _findDraw(uint256 drawId) internal virtual returns (Draw memory draw) {
  //   return draws[drawId]
  // }

  function _claimDraw(bytes32 userClaimedDraws, uint256 drawId, uint256 _currentDrawId) internal returns (bytes32) {
    uint8 drawIndex = _drawIdToClaimIndex(drawId, _currentDrawId);
    bool isClaimed = _readLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);

    require(!isClaimed, "ERROR3");

    return _writeLastClaimFromClaimedHistory(userClaimedDraws, drawIndex);
  }

  function _drawIdToClaimIndex(uint256 drawId, uint256 _currentDrawId) view internal returns (uint8){
    require(drawId + 256 > _currentDrawId, "ERROR");
    require(drawId <= _currentDrawId, "ERROR2");

    // How many indices in the past the given draw is
    uint256 deltaIndex = _currentDrawId - drawId;

    // Find absolute draw index by using currentDraw index and delta
    return uint8(currentDrawIndex - deltaIndex);
  }


  function _readLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bool) {
    uint256 mask = (uint256(1)) << (_drawIndex);
    return ((uint256(_userClaimedDraws) & mask) >> (_drawIndex)) != 0;    
  }

  /// @notice Updates a 256 bit word with a 32 bit representation of a block number at a particular index
  /// @param _userClaimedDraws The 256 word
  /// @param _drawIndex The index within that word (0 to 7)
  function _writeLastClaimFromClaimedHistory(bytes32 _userClaimedDraws, uint8 _drawIndex) internal pure returns (bytes32) { 
    uint256 mask =  (uint256(1)) << (_drawIndex);
    return bytes32(uint256(_userClaimedDraws) | mask); 
  }

}