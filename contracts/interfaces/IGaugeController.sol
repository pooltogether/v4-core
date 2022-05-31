// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

interface IGaugeController {
    function getScaledAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime) external view returns (uint256);
}
