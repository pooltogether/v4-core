// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../DrawCalculator.sol";
import "../libraries/DrawLib.sol";

contract DrawCalculatorHarness is DrawCalculator {

  constructor(
    address _owner,
    ITicket _ticket,
    IDrawHistory _drawHistory,
    PrizeDistributionHistory _prizeDistributionHistory
  ) DrawCalculator(_owner, _ticket, _drawHistory, _prizeDistributionHistory) { }

  function calculateDistributionIndex(uint256 _randomNumberThisPick, uint256 _winningRandomNumber, uint256[] memory _masks) public pure returns (uint256) {
    return _calculateDistributionIndex(_randomNumberThisPick, _winningRandomNumber, _masks);
  }

  function createBitMasks(DrawLib.PrizeDistribution calldata _prizeDistribution) public pure returns (uint256[] memory) {
    return _createBitMasks(_prizeDistribution);
  }

  ///@notice Calculates the expected prize fraction per prizeDistribution and prizeDistributionIndex
  ///@param _prizeDistribution prizeDistribution struct for Draw
  ///@param _prizeDistributionIndex Index of the prize distributions array to calculate
  ///@return returns the fraction of the total prize
  function calculatePrizeDistributionFraction(DrawLib.PrizeDistribution calldata _prizeDistribution, uint256 _prizeDistributionIndex) external pure returns (uint256)
  {
    return _calculatePrizeDistributionFraction(_prizeDistribution, _prizeDistributionIndex);
  }

  function numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeDistributionIndex) external pure returns (uint256) {
    return _numberOfPrizesForIndex(_bitRangeSize, _prizeDistributionIndex);
  }

  function calculateNumberOfUserPicks(DrawLib.PrizeDistribution memory _prizeDistribution, uint256 _normalizedUserBalance) external pure returns (uint256){
    return _calculateNumberOfUserPicks(_prizeDistribution, _normalizedUserBalance);
  }
}
