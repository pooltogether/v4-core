// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../DrawCalculatorV2.sol";

contract DrawCalculatorV2Harness is DrawCalculatorV2 {
    constructor(
        ITicket _ticket,
        IDrawBuffer _drawBuffer,
        IPrizeDistributionSource _prizeDistributionSource
    ) DrawCalculatorV2(_ticket, _drawBuffer, _prizeDistributionSource) {}

    function calculateTierIndex(
        uint256 _randomNumberThisPick,
        uint256 _winningRandomNumber,
        uint256[] memory _masks
    ) public pure returns (uint256) {
        return _calculateTierIndex(_randomNumberThisPick, _winningRandomNumber, _masks);
    }

    function createBitMasks(IPrizeDistributionSource.PrizeDistribution calldata _prizeDistribution)
        public
        pure
        returns (uint256[] memory)
    {
        return _createBitMasks(_prizeDistribution);
    }

    ///@notice Calculates the expected prize fraction per prizeDistribution and prizeTierIndex
    ///@param _prizeDistribution prizeDistribution struct for Draw
    ///@param _prizeTierIndex Index of the prize tiers array to calculate
    ///@return returns the fraction of the total prize
    function calculatePrizeTierFraction(
        IPrizeDistributionSource.PrizeDistribution calldata _prizeDistribution,
        uint256 _prizeTierIndex
    ) external pure returns (uint256) {
        return _calculatePrizeTierFraction(_prizeDistribution, _prizeTierIndex);
    }

    function numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeTierIndex)
        external
        pure
        returns (uint256)
    {
        return _numberOfPrizesForIndex(_bitRangeSize, _prizeTierIndex);
    }

    function calculateNumberOfUserPicks(
        IPrizeDistributionSource.PrizeDistribution memory _prizeDistribution,
        uint256 _normalizedUserBalance
    ) external pure returns (uint64) {
        return _calculateNumberOfUserPicks(_prizeDistribution, _normalizedUserBalance);
    }
}
