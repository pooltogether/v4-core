// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "@pooltogether/v4-periphery/contracts/libraries/BinarySearchLib.sol";

import "./interfaces/IPrizeConfigHistory.sol";

/**
 * @title  PoolTogether V4 PrizeConfigHistory
 * @author PoolTogether Inc Team
 * @notice Contract to store prize configurations
 */
contract PrizeConfigHistory is IPrizeConfigHistory, Manageable {
    /// @dev The uint32[] type is extended with a binarySearch(uint32) function.
    using BinarySearchLib for uint32[];

    /* ============ Variables ============ */

    /**
     * @notice Ordered array of Draw IDs.
     * @dev The history, with sequentially ordered ids, can be searched using binary search.
            The binary search will find index of a drawId (atOrBefore) using a specific drawId (at).
            When a new Draw ID is added to the history, a corresponding mapping of the ID is
            updated in the prizeConfigs mapping.
    */
    uint32[] internal history;

    /**
     * @notice Mapping of Draw ID to PrizeConfig struct.
     * @dev drawId -> PrizeConfig
     * @dev The prizeConfigs mapping is updated when a new Draw ID is added to the history.
     */
    mapping(uint32 => PrizeConfig) internal prizeConfigs;

    /* ============ Events ============ */

    /**
     * @notice Emit when a new PrizeConfig is added to history
     * @param drawId    Draw ID at which the PrizeConfig was pushed and is since valid
     * @param prizeConfig PrizeConfig struct
     */
    event PrizeConfigPushed(uint32 indexed drawId, PrizeConfig prizeConfig);

    /**
     * @notice Emit when existing PrizeConfig is updated in history
     * @param drawId    Draw ID at which the PrizeConfig was set and is since valid
     * @param prizeConfig PrizeConfig struct
     */
    event PrizeConfigSet(uint32 indexed drawId, PrizeConfig prizeConfig);

    /* ============ Constructor ============ */

    /**
     * @notice PrizeConfigHistory constructor
     * @param _owner Address of the owner
     */
    constructor(address _owner) Ownable(_owner) {}

    /* ============ External Functions ============ */

    /// @inheritdoc IPrizeConfigHistory
    function count() external view override returns (uint256) {
        return history.length;
    }

    /// @inheritdoc IPrizeConfigHistory
    function getNewestDrawId() external view override returns (uint32) {
        return history[history.length - 1];
    }

    /// @inheritdoc IPrizeConfigHistory
    function getOldestDrawId() external view override returns (uint32) {
        return history[0];
    }

    /// @inheritdoc IPrizeConfigHistory
    function getPrizeConfig(uint32 _drawId)
        external
        view
        override
        returns (PrizeConfig memory prizeConfig)
    {
        require(_drawId > 0, "PrizeConfHistory/draw-id-gt-zero");
        return prizeConfigs[history.binarySearch(_drawId)];
    }

    /// @inheritdoc IPrizeConfigHistory
    function getPrizeConfigAtIndex(uint256 _index)
        external
        view
        override
        returns (PrizeConfig memory prizeConfig)
    {
        return prizeConfigs[uint32(_index)];
    }

    // @inheritdoc IPrizeConfigHistory
    function getPrizeConfigList(uint32[] calldata _drawIds)
        external
        view
        override
        returns (PrizeConfig[] memory prizeConfigList)
    {
        uint256 _length = _drawIds.length;
        PrizeConfig[] memory _data = new PrizeConfig[](_length);

        for (uint256 index = 0; index < _length; index++) {
            _data[index] = prizeConfigs[history.binarySearch(_drawIds[index])];
        }

        return _data;
    }

    /// @inheritdoc IPrizeConfigHistory
    function popAndPush(PrizeConfig calldata _newPrizeConfig)
        external
        override
        onlyOwner
        returns (uint32)
    {
        uint256 length = history.length;

        require(length > 0, "PrizeConfHistory/history-empty");
        require(history[length - 1] == _newPrizeConfig.drawId, "PrizeConfHistory/invalid-draw-id");

        _replace(_newPrizeConfig);

        return _newPrizeConfig.drawId;
    }

    /// @inheritdoc IPrizeConfigHistory
    function push(PrizeConfig calldata _nextPrizeConfig) external override onlyManagerOrOwner {
        _push(_nextPrizeConfig);
    }

    /// @inheritdoc IPrizeConfigHistory
    function replace(PrizeConfig calldata _newPrizeConfig) external override onlyOwner {
        _replace(_newPrizeConfig);
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Push PrizeConfigHistory struct onto history array.
     * @param _prizeConfig New PrizeConfig struct to push onto history array
     */
    function _push(PrizeConfig memory _prizeConfig) internal {
        uint256 _historyLength = history.length;

        if (_historyLength > 0) {
            uint256 _id = history[uint32(_historyLength - 1)];

            require(_prizeConfig.drawId > uint32(_id), "PrizeConfHistory/nonsequentialId");
        }

        history.push(_prizeConfig.drawId);
        prizeConfigs[uint32(_historyLength)] = _prizeConfig;

        emit PrizeConfigPushed(_prizeConfig.drawId, _prizeConfig);
    }

    /**
     * @notice Replace PrizeConfig struct from history array.
     * @dev Performs a binary search to find which index in the history array contains the drawId to replace.
     * @param _prizeConfig New PrizeConfig struct that will replace the previous PrizeConfig at the corresponding index.
     */
    function _replace(PrizeConfig calldata _prizeConfig) internal {
        require(history.length > 0, "PrizeConfHistory/no-prize-conf");

        uint32 oldestDrawId = history[0];
        require(_prizeConfig.drawId >= oldestDrawId, "PrizeConfHistory/drawId-beyond");

        uint32 index = history.binarySearch(_prizeConfig.drawId);
        require(history[index] == _prizeConfig.drawId, "PrizeConfHistory/drawId-mismatch");

        prizeConfigs[index] = _prizeConfig;
        emit PrizeConfigSet(_prizeConfig.drawId, _prizeConfig);
    }
}
