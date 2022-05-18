// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

/**
 * @title  PoolTogether V4 IGaugeReward
 * @author PoolTogether Inc Team
 * @notice The GaugeReward interface.
 */
interface IGaugeReward {
    /**
     * @notice Fallback function to call in GaugeController after a user has increased their gauge stake.
     * @param gauge Address of the gauge to increase stake for
     * @param user Address of the user to increase stake for
     * @param oldStakeBalance Old stake balance of the user
     */
    function afterIncreaseGauge(
        address gauge,
        address user,
        uint256 oldStakeBalance
    ) external;

    /**
     * @notice Fallback function to call in GaugeController after a user has decreased his gauge stake.
     * @param gauge Address of the gauge to decrease stake for
     * @param user Address of the user to decrease stake for
     * @param oldStakeBalance Old stake balance of the user
     */
    function afterDecreaseGauge(
        address gauge,
        address user,
        uint256 oldStakeBalance
    ) external;
}
