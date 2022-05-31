// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../DrawCalculatorV3.sol";

contract DrawCalculatorV3Harness is DrawCalculatorV3 {
    constructor(
        IGaugeController _gaugeController,
        IDrawBuffer _drawBuffer,
        IPrizeConfigHistory _prizeConfigHistory,
        address _owner
    ) DrawCalculatorV3(_gaugeController, _drawBuffer, _prizeConfigHistory, _owner) {}

    function calculateTierIndex(
        uint256 _randomNumberThisPick,
        uint256 _winningRandomNumber,
        uint256[] memory _masks
    ) public pure returns (uint256) {
        return _calculateTierIndex(_randomNumberThisPick, _winningRandomNumber, _masks);
    }

    function createBitMasks(uint8 _matchCardinality, uint8 _bitRangeSize)
        public
        pure
        returns (uint256[] memory)
    {
        return _createBitMasks(_matchCardinality, _bitRangeSize);
    }

    function calculatePrizeTierFraction(
        uint256 _prizeFraction,
        uint8 _bitRangeSize,
        uint256 _prizeConfigIndex
    ) external pure returns (uint256) {
        return _calculatePrizeTierFraction(_prizeFraction, _bitRangeSize, _prizeConfigIndex);
    }

    function numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeConfigIndex)
        external
        pure
        returns (uint256)
    {
        return _numberOfPrizesForIndex(_bitRangeSize, _prizeConfigIndex);
    }
}
