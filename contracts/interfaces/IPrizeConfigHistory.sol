// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

/**
 * @title  PoolTogether V4 IPrizeConfigHistory
 * @author PoolTogether Inc Team
 * @notice IPrizeConfigHistory is the base contract for PrizeConfigHistory
 */
interface IPrizeConfigHistory {
    /**
     * @notice PrizeConfig struct read every draw.
     * @param bitRangeSize Number of bits in decimal allocated to each division
     * @param matchCardinality Number of numbers to consider in the 256 bit random number. Must be > 1 and < 256/bitRangeSize.
     * @param maxPicksPerUser Maximum number of picks a user can make in this draw
     * @param drawId Draw ID at which the PrizeConfig was pushed and is since valid
     * @param expiryDuration Length of time in seconds the PrizeDistribution is valid for. Relative to the Draw.timestamp.
     * @param endTimestampOffset The end time offset in seconds from which Ticket balances are calculated.
     * @param poolStakeCeiling Total globally configured POOL staking ceiling
     * @param prize Total prize amount available for this draw
     * @param tiers Array of prize tiers percentages, expressed in fraction form with base 1e9. Ordering: index0: grandPrize, index1: runnerUp, etc.
     */
    struct PrizeConfig {
        uint8 bitRangeSize;
        uint8 matchCardinality;
        uint16 maxPicksPerUser;
        uint32 drawId;
        uint32 expiryDuration;
        uint32 endTimestampOffset;
        uint128 poolStakeCeiling;
        uint256 prize;
        uint32[16] tiers;
    }

    /**
     * @notice Returns the number of PrizeConfig structs pushed
     * @return The number of prize config that have been pushed
     */
    function count() external view returns (uint256);

    /**
     * @notice Returns last Draw ID recorded in the history.
     * @return Draw ID of the last PrizeConfig record
     */
    function getNewestDrawId() external view returns (uint32);

    /**
     * @notice Returns first Draw ID used to initialize history.
     * @return Draw ID of the first PrizeConfig record
     */
    function getOldestDrawId() external view returns (uint32);

    /**
     * @notice Returns PrizeConfig struct for the passed Draw ID.
     * @param drawId Draw ID for which to return PrizeConfig struct
     * @return The PrizeConfig struct for the passed Draw ID
     */
    function getPrizeConfig(uint32 drawId) external view returns (PrizeConfig memory);

    /**
     * @notice Returns the PrizeConfig struct at the given index.
     * @param index Index at which the PrizeConfig struct is stored
     * @return The PrizeConfig struct at the given index
     */
    function getPrizeConfigAtIndex(uint256 index) external view returns (PrizeConfig memory);

    /**
     * @notice Returns a list of PrizeConfig from the history array.
     * @param drawIds List of Draw IDs for which to return PrizeConfig structs
     * @return The list of PrizeConfig structs for the passed Draw IDs
     */
    function getPrizeConfigList(uint32[] calldata drawIds)
        external
        view
        returns (PrizeConfig[] memory);

    /**
     * @notice Push PrizeConfigHistory struct onto history array.
     * @dev Callable only by the owner.
     * @param prizeConfig Updated PrizeConfigHistory struct
     * @return Draw ID at which the PrizeConfig was pushed and is since valid
     */
    function popAndPush(PrizeConfig calldata prizeConfig) external returns (uint32);

    /**
     * @notice Push PrizeConfig struct onto history array.
     * @dev Callable only by the owner or manager.
     * @param prizeConfig New PrizeConfig struct to push onto the history array
     */
    function push(PrizeConfig calldata prizeConfig) external;

    /**
     * @notice Replace PrizeConfig struct from history array.
     * @dev Callable only by the owner.
     * @param prizeConfig New PrizeConfig struct that will replace the previous PrizeConfig at the corresponding index
     */
    function replace(PrizeConfig calldata prizeConfig) external;
}
