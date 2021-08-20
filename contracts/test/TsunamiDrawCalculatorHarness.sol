// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../TsunamiDrawCalculator.sol";

contract TsunamiDrawCalculatorHarness is TsunamiDrawCalculator {
  
  function findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 index, uint8 _bitRangeSize, uint8 _maskValue) external pure returns(bool) {
    require(_maskValue == (2 ** _bitRangeSize) - 1);
    return _findBitMatchesAtIndex(word1, word2, (index * _bitRangeSize), _maskValue);
  }
}
