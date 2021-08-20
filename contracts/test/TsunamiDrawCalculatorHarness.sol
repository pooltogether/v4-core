// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../TsunamiDrawCalculator.sol";

contract TsunamiDrawCalculatorHarness is TsunamiDrawCalculator {
  
  ///@notice helper function to return if the bits in a word match at a particular index
  ///@param word1 word1 to index and match
  ///@param word2 word2 to index and match
  ///@param indexOffset 0 start index including 4-bit offset (i.e. 8 observes index 2 = 4 * 2)
  ///@param _bitRangeMaskValue _bitRangeMaskValue must be equal to (_bitRangeSize ^ 2) - 1
  ///@return true if there is a match, false otherwise
  function _findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 indexOffset, uint8 _bitRangeMaskValue)
    internal pure returns(bool) {
    uint256 mask = (uint256(_bitRangeMaskValue)) << indexOffset;  // generate a mask of _bitRange length at the specified offset
    return (uint256(word1) & mask) == (uint256(word2) & mask);
  }

  function findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 index, uint8 _bitRangeSize, uint8 _maskValue) external pure returns(bool) {
    require(_maskValue == (2 ** _bitRangeSize) - 1);
    return _findBitMatchesAtIndex(word1, word2, (index * _bitRangeSize), _maskValue);
  }
}
