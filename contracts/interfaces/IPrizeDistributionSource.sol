// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./IPrizeDistributionBuffer.sol";

/** @title IPrizeDistributionSource
 * @author PoolTogether Inc Team
 * @notice The PrizeDistributionSource interface.
 */
interface IPrizeDistributionSource {
    /**
     * @notice Gets PrizeDistribution list from array of drawIds
     * @param drawIds drawIds to get PrizeDistribution for
     * @return prizeDistributionList
     */
    function getPrizeDistributions(uint32[] calldata drawIds)
        external
        view
        returns (IPrizeDistributionBuffer.PrizeDistribution[] memory);
}
