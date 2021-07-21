// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

abstract contract IWaveModel {
  function calculate(uint256 winningNumber, uint256 prize, uint256 totalDeposits, uint256 userBalance, uint256 randomNumber) virtual external returns(uint256 prizeAmount);
}