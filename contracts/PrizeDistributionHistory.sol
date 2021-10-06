// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBufferLib.sol";
import "./interfaces/IPrizeDistributionHistory.sol";

/**
  * @title  PoolTogether V4 PrizeDistributionHistory
  * @author PoolTogether Inc Team
  * @notice The PrizeDistributionHistory stores historic PrizeDistribution for each drawId.
            Storage of the PrizeDistributions is handled by a ring buffer with a max cardinality
            of 256 or roughly 5 years of history with a weekly draw cadence.
*/
contract PrizeDistributionHistory is IPrizeDistributionHistory, Manageable {
    using DrawRingBufferLib for DrawRingBufferLib.Buffer;

    /// @notice The maximum cardinality of the prize distribution ring buffer.
    /// @dev even with daily draws, 256 will give us over 8 months of history.
    uint256 internal constant MAX_CARDINALITY = 256;

    /// @notice The ceiling for prize distributions.  1e9 = 100%.
    /// @dev It's fixed point 9 because 1e9 is the largest "1" that fits into 2**32
    uint256 internal constant DISTRIBUTION_CEILING = 1e9;

    /// @notice Emitted when the contract is deployed.
    /// @param cardinality The maximum number of records in the buffer before they begin to expire.
    event Deployed(uint8 cardinality);

    /// @notice PrizeDistribution ring buffer history.
    DrawLib.PrizeDistribution[MAX_CARDINALITY] internal _prizeDistributionsRingBuffer;

    /// @notice Ring buffer data (nextIndex, lastDrawId, cardinality)
    DrawRingBufferLib.Buffer internal _prizeDistributionsRingBufferData;

    /* ============ Constructor ============ */

    /**
     * @notice Constructor for PrizeDistributionHistory
     * @param _owner Address of the PrizeDistributionHistory owner
     * @param _cardinality Cardinality of the `_prizeDistributionsRingBufferData`
     */
    constructor(address _owner, uint8 _cardinality) Ownable(_owner) {
        _prizeDistributionsRingBufferData.cardinality = _cardinality;
        emit Deployed(_cardinality);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IPrizeDistributionHistory
    function getPrizeDistribution(uint32 _drawId)
        external
        view
        override
        returns (DrawLib.PrizeDistribution memory)
    {
        return _getPrizeDistribution(_prizeDistributionsRingBufferData, _drawId);
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getPrizeDistributions(uint32[] calldata _drawIds)
        external
        view
        override
        returns (DrawLib.PrizeDistribution[] memory)
    {
        DrawRingBufferLib.Buffer memory buffer = _prizeDistributionsRingBufferData;
        DrawLib.PrizeDistribution[] memory _prizeDistributions = new DrawLib.PrizeDistribution[](
            _drawIds.length
        );

        for (uint256 i = 0; i < _drawIds.length; i++) {
            _prizeDistributions[i] = _getPrizeDistribution(buffer, _drawIds[i]);
        }

        return _prizeDistributions;
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getPrizeDistributionCount() external view override returns (uint32) {
        DrawRingBufferLib.Buffer memory buffer = _prizeDistributionsRingBufferData;

        if (buffer.lastDrawId == 0) {
            return 0;
        }

        uint32 bufferNextIndex = buffer.nextIndex;

        // If the buffer is full return the cardinality, else retun the nextIndex
        if (_prizeDistributionsRingBuffer[bufferNextIndex].matchCardinality != 0) {
            return buffer.cardinality;
        } else {
            return bufferNextIndex;
        }
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getNewestPrizeDistribution()
        external
        view
        override
        returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId)
    {
        DrawRingBufferLib.Buffer memory buffer = _prizeDistributionsRingBufferData;

        return (
            _prizeDistributionsRingBuffer[buffer.getIndex(buffer.lastDrawId)],
            buffer.lastDrawId
        );
    }

    /// @inheritdoc IPrizeDistributionHistory
    function getOldestPrizeDistribution()
        external
        view
        override
        returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId)
    {
        DrawRingBufferLib.Buffer memory buffer = _prizeDistributionsRingBufferData;

        // if the ring buffer is full, the oldest is at the nextIndex
        prizeDistribution = _prizeDistributionsRingBuffer[buffer.nextIndex];

        // The PrizeDistribution at index 0 IS by default the oldest prizeDistribution.
        if (buffer.lastDrawId == 0) {
            drawId = 0; // return 0 to indicate no prizeDistribution ring buffer history
        } else if (prizeDistribution.bitRangeSize == 0) {
            // IF the next PrizeDistribution.bitRangeSize == 0 the ring buffer HAS NOT looped around so the oldest is the first entry.
            prizeDistribution = _prizeDistributionsRingBuffer[0];
            drawId = (buffer.lastDrawId + 1) - buffer.nextIndex;
        } else {
            // Calculates the drawId using the ring buffer cardinality
            // Sequential drawIds are gauranteed by DrawRingBufferLib.push()
            drawId = (buffer.lastDrawId + 1) - buffer.cardinality;
        }
    }

    /// @inheritdoc IPrizeDistributionHistory
    function pushPrizeDistribution(
        uint32 _drawId,
        DrawLib.PrizeDistribution calldata _prizeDistribution
    ) external override onlyManagerOrOwner returns (bool) {
        return _pushPrizeDistribution(_drawId, _prizeDistribution);
    }

    /// @inheritdoc IPrizeDistributionHistory
    function setPrizeDistribution(
        uint32 _drawId,
        DrawLib.PrizeDistribution calldata _prizeDistribution
    ) external override onlyOwner returns (uint32) {
        DrawRingBufferLib.Buffer memory buffer = _prizeDistributionsRingBufferData;
        uint32 index = buffer.getIndex(_drawId);
        _prizeDistributionsRingBuffer[index] = _prizeDistribution;

        emit PrizeDistributionSet(_drawId, _prizeDistribution);

        return _drawId;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Gets the PrizeDistributionHistory for a drawId
     * @param _buffer DrawRingBufferLib.Buffer
     * @param _drawId drawId
     */
    function _getPrizeDistribution(DrawRingBufferLib.Buffer memory _buffer, uint32 _drawId)
        internal
        view
        returns (DrawLib.PrizeDistribution memory)
    {
        return _prizeDistributionsRingBuffer[_buffer.getIndex(_drawId)];
    }

    /**
     * @notice Set newest PrizeDistributionHistory in ring buffer storage.
     * @param _drawId       drawId
     * @param _prizeDistribution PrizeDistributionHistory struct
     */
    function _pushPrizeDistribution(
        uint32 _drawId,
        DrawLib.PrizeDistribution calldata _prizeDistribution
    ) internal returns (bool) {
        
        require(_drawId > 0, "DrawCalc/draw-id-gt-0");
        require(_prizeDistribution.matchCardinality > 0, "DrawCalc/matchCardinality-gt-0");
        require(
            _prizeDistribution.bitRangeSize <= 256 / _prizeDistribution.matchCardinality,
            "DrawCalc/bitRangeSize-too-large"
        );

        require(_prizeDistribution.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
        require(_prizeDistribution.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");

        // ensure that the sum of the distributions are not gt 100% and record number of non-zero distributions entries
        uint256 sumTotalDistributions = 0;
        uint256 nonZeroDistributions = 0;
        uint256 distributionsLength = _prizeDistribution.distributions.length;

        for (uint256 index = 0; index < distributionsLength; index++) {
            sumTotalDistributions += _prizeDistribution.distributions[index];

            if (_prizeDistribution.distributions[index] > 0) {
                nonZeroDistributions++;
            }
        }

        // Each distribution amount stored as uint32 - summed can't exceed 1e9
        require(sumTotalDistributions <= DISTRIBUTION_CEILING, "DrawCalc/distributions-gt-100%");

        require(
            _prizeDistribution.matchCardinality >= nonZeroDistributions,
            "DrawCalc/matchCardinality-gte-distributions"
        );

        DrawRingBufferLib.Buffer memory buffer = _prizeDistributionsRingBufferData;

        // store the PrizeDistribution in the ring buffer
        _prizeDistributionsRingBuffer[buffer.nextIndex] = _prizeDistribution;

        // update the ring buffer data
        _prizeDistributionsRingBufferData = buffer.push(_drawId);

        emit PrizeDistributionSet(_drawId, _prizeDistribution);

        return true;
    }
}
