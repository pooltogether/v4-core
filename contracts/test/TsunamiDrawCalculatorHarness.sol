// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../TsunamiDrawCalculator.sol";
import "../libraries/DrawLib.sol";

contract TsunamiDrawCalculatorHarness is TsunamiDrawCalculator {

  constructor(
    ITicket _ticket,
    IDrawHistory _drawHistory,
    TsunamiDrawSettingsHistory _drawSettingsHistory
  ) TsunamiDrawCalculator(_ticket, _drawHistory, _drawSettingsHistory) { }

  function calculateDistributionIndex(uint256 _randomNumberThisPick, uint256 _winningRandomNumber, uint256[] memory _masks) public view returns (uint256) {
    return _calculateDistributionIndex(_randomNumberThisPick, _winningRandomNumber, _masks);
  }

  function createBitMasks(DrawLib.TsunamiDrawSettings calldata _drawSettings) public view returns (uint256[] memory) {
    return _createBitMasks(_drawSettings);
  }

  ///@notice Calculates the expected prize fraction per TsunamiDrawCalculatorSettings and prizeDistributionIndex
  ///@param _drawSettings TsunamiDrawCalculatorSettings struct for Draw
  ///@param _prizeDistributionIndex Index of the prize distribution array to calculate
  ///@return returns the fraction of the total prize
  function calculatePrizeDistributionFraction(DrawLib.TsunamiDrawSettings calldata _drawSettings, uint256 _prizeDistributionIndex) external view returns (uint256)
  {
    return _calculatePrizeDistributionFraction(_drawSettings, _prizeDistributionIndex);
  }

  function numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeDistributionIndex) external pure returns (uint256) {
    return _numberOfPrizesForIndex(_bitRangeSize, _prizeDistributionIndex);
  }

  function getNormalizedBalancesAt(address _user, uint32[] memory _timestamps, DrawLib.TsunamiDrawSettings[] calldata _drawSettings) external view returns (uint256[] memory) {
    // nasty hack
    DrawLib.Draw[] memory _draws = new DrawLib.Draw[](_timestamps.length);
    for (uint256 i = 0; i < _timestamps.length; i++) {
      _draws[i].timestamp = _timestamps[i];
    }
    return _getNormalizedBalancesAt(_user, _draws, _drawSettings);
  }

  function calculateNumberOfUserPicks(DrawLib.TsunamiDrawSettings memory _drawSettings, uint256 _normalizedUserBalance) external view returns (uint256){
    return _calculateNumberOfUserPicks(_drawSettings, _normalizedUserBalance);
  }
}
