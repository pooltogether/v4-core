// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./ITicket.sol";
import "./IDrawBuffer.sol";
import "./IGaugeController.sol";
import "./IPrizeConfigHistory.sol";

/**
 * @title  PoolTogether V4 IDrawCalculatorV3
 * @author PoolTogether Inc Team
 * @notice The DrawCalculator interface.
 */
interface IDrawCalculatorV3 {
    /**
     * @notice Calculates the awardable prizes for a user for Multiple Draws. Typically called by a PrizeDistributor.
     * @param ticket Address of the ticket to calculate awardable prizes for
     * @param user Address of the user for which to calculate awardable prizes for
     * @param drawIds Array of DrawIds for which to calculate awardable prizes for
     * @param data ABI encoded pick indices for all Draws. Expected to be winning picks. Pick indices must be less than the totalUserPicks.
     * @return List of awardable prize amounts ordered by drawId.
     * @return List of prize counts ordered by tiers.
     * @return Pick indices for each drawId.
     */
    function calculate(
        ITicket ticket,
        address user,
        uint32[] calldata drawIds,
        bytes calldata data
    )
        external
        view
        returns (
            uint256[] memory,
            bytes memory,
            uint64[][] memory
        );

    /**
     * @notice Calculates picks for a user for Multiple Draws.
     * @param ticket Address of the ticket to calculate picks for
     * @param user Address of the user for which to calculate picks for
     * @param drawIds Array of DrawIds for which to calculate picks for
     */
    function calculateUserPicks(
        ITicket ticket,
        address user,
        uint32[] calldata drawIds
    ) external view returns (uint64[] memory);

    /**
     * @notice Returns DrawBuffer address.
     * @return The DrawBuffer address
     */
    function getDrawBuffer() external view returns (IDrawBuffer);

    /**
     * @notice Returns GaugeController address.
     * @return The GaugeController address
     */
    function getGaugeController() external view returns (IGaugeController);

    /**
     * @notice Returns PrizeConfigHistory address.
     * @return The PrizeConfigHistory address
     */
    function getPrizeConfigHistory() external view returns (IPrizeConfigHistory);

    /**
     * @notice Returns the total number of picks for a prize pool / ticket.
     * @param ticket Address of the ticket to get total picks for
     * @param startTime Timestamp at which the draw starts
     * @param endTime Timestamp at which the draw ends
     * @param poolStakeCeiling Globally configured pool stake ceiling
     * @param bitRange Number of bits allocated to each division
     * @param cardinality Number of sub-divisions of a random number
     * @return Total number of picks for this prize pool / ticket
     */
    function getTotalPicks(
        ITicket ticket,
        uint256 startTime,
        uint256 endTime,
        uint256 poolStakeCeiling,
        uint8 bitRange,
        uint8 cardinality
    ) external view returns (uint256);
}
