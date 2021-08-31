// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../TsunamiDrawCalculator.sol";

contract TsunamiDrawCalculatorHarness is TsunamiDrawCalculator {
  
  function calculateDistributionIndex(uint256 _randomNumberThisPick, uint256 _winningRandomNumber, uint256[] memory _masks) public view returns (uint256) {
    return _calculateDistributionIndex(_randomNumberThisPick, _winningRandomNumber, _masks); 
  }

  function createBitMasks(DrawSettings calldata _drawSettings) public view returns (uint256[] memory) {
    return _createBitMasks(_drawSettings);
  }
}
