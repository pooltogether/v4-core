// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../TsunamiDrawCalculator.sol";

contract TsunamiDrawCalculatorHarness is TsunamiDrawCalculator {
  
   function getValueAtIndex(uint256 word, uint256 index, uint8 range) external view returns(uint256) {
     return _getValueAtIndex(word, index, range);
   }

}
