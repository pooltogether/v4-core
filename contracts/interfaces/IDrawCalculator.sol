// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface IDrawCalculator {
    
  function calculate(address _user, DrawLib.Draw[] calldata _draws, bytes calldata _pickIndicesForDraws)
    external view returns (uint96[] memory);
}