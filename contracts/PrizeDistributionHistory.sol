// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBufferLib.sol";
import "./interfaces/IPrizeDistributionHistory.sol";

/**
  * @title  PoolTogether V4 PrizeDistributionHistory
  * @author PoolTogether Inc Team
  * @notice The PrizeDistributionHistory stores individual PrizeDistributions for each Draw.drawId.
            PrizeDistributions parameters like cardinality, bitRange, distributions, number of picks
            and prize. The settings determine the specific distribution model for each individual
            draw. Storage of the PrizeDistribution(s) is handled by ring buffer with a max cardinality
            of 256 or roughly 5 years of history with a weekly draw cadence.
*/
contract PrizeDistributionHistory is IPrizeDistributionHistory, Manageable {
  using DrawRingBufferLib for DrawRingBufferLib.Buffer;

  uint256 internal constant MAX_CARDINALITY = 256;

  uint256 internal constant DISTRIBUTION_CEILING = 1e9;
  event Deployed(uint8 cardinality);

  /// @notice PrizeDistributions ring buffer history.
  DrawLib.PrizeDistribution[MAX_CARDINALITY] internal _prizeDistributionsRingBuffer;

  /// @notice Ring buffer data (nextIndex, lastDrawId, cardinality)
  DrawRingBufferLib.Buffer internal prizeDistributionsRingBufferData;

  /* ============ Constructor ============ */

  /**
    * @notice Constructor for PrizeDistributionHistory
    * @param _owner Address of the PrizeDistributionHistory owner
    * @param _cardinality Cardinality of the `prizeDistributionsRingBufferData`
   */
  constructor(
    address _owner,
    uint8 _cardinality
  ) Ownable(_owner) {
    prizeDistributionsRingBufferData.cardinality = _cardinality;
    emit Deployed(_cardinality);
  }

  /* ============ External Functions ============ */

  /// @inheritdoc IPrizeDistributionHistory
  function getPrizeDistribution(uint32 _drawId) external override view returns(DrawLib.PrizeDistribution memory) {
    return _getPrizeDistributions(prizeDistributionsRingBufferData, _drawId);
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getPrizeDistributions(uint32[] calldata _drawIds) external override view returns(DrawLib.PrizeDistribution[] memory) {
    DrawRingBufferLib.Buffer memory buffer = prizeDistributionsRingBufferData;
    DrawLib.PrizeDistribution[] memory _prizeDistributions = new DrawLib.PrizeDistribution[](_drawIds.length);
    for (uint256 i = 0; i < _drawIds.length; i++) {
      _prizeDistributions[i] = _getPrizeDistributions(buffer, _drawIds[i]);
    }
    return _prizeDistributions;
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getPrizeDistributionCount() external override view returns (uint32) {
    DrawRingBufferLib.Buffer memory buffer = prizeDistributionsRingBufferData;

    if (buffer.lastDrawId == 0) {
      return 0;
    }

    uint32 bufferNextIndex = buffer.nextIndex;

    if (_prizeDistributionsRingBuffer[bufferNextIndex].matchCardinality != 0) {
      return buffer.cardinality;
    } else {
      return bufferNextIndex;
    }
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getNewestPrizeDistribution() external override view returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId) {
    DrawRingBufferLib.Buffer memory buffer = prizeDistributionsRingBufferData;
    return (_prizeDistributionsRingBuffer[buffer.getIndex(buffer.lastDrawId)], buffer.lastDrawId);
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getOldestPrizeDistribution() external override view returns (DrawLib.PrizeDistribution memory prizeDistribution, uint32 drawId) {
    DrawRingBufferLib.Buffer memory buffer = prizeDistributionsRingBufferData;
    prizeDistribution = _prizeDistributionsRingBuffer[buffer.nextIndex];

    // IF the next PrizeDistributions.bitRangeSize == 0 the ring buffer HAS NOT looped around.
    // The PrizeDistributions at index 0 IS by defaut the oldest prizeDistribution.
    if (buffer.lastDrawId == 0) {
      drawId = 0; // return 0 to indicate no prizeDistribution ring buffer history
    } else if (prizeDistribution.bitRangeSize == 0) {
      prizeDistribution = _prizeDistributionsRingBuffer[0];
      drawId = (buffer.lastDrawId + 1) - buffer.nextIndex; // 2 + 1 - 2 = 1 | [1,2,0]
    } else {
      // Calculates the Draw.drawID using the ring buffer length and SEQUENTIAL id(s)
      // Sequential "guaranteedness" is handled in DrawRingBufferLib.push()
      drawId = (buffer.lastDrawId + 1) - buffer.cardinality; // 4 + 1 - 3 = 2 | [4,2,3]
    }
  }

  /// @inheritdoc IPrizeDistributionHistory
  function pushPrizeDistribution(uint32 _drawId, DrawLib.PrizeDistribution calldata _prizeDistribution) external override onlyManagerOrOwner returns (bool) {
    return _pushPrizeDistribution(_drawId, _prizeDistribution);
  }

  /// @inheritdoc IPrizeDistributionHistory
  function setPrizeDistribution(uint32 _drawId, DrawLib.PrizeDistribution calldata _prizeDistribution) external override onlyOwner returns (uint32) {
    DrawRingBufferLib.Buffer memory buffer = prizeDistributionsRingBufferData;
    uint32 index = buffer.getIndex(_drawId);
    _prizeDistributionsRingBuffer[index] = _prizeDistribution;
    emit PrizeDistributionsSet(_drawId, _prizeDistribution);
    return _drawId;
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Gets the PrizeDistributionHistory for a Draw.drawID
    * @param _prizeDistributionsRingBufferData DrawRingBufferLib.Buffer
    * @param drawId Draw.drawId
   */
  function _getPrizeDistributions(
    DrawRingBufferLib.Buffer memory _prizeDistributionsRingBufferData,
    uint32 drawId
  ) internal view returns (DrawLib.PrizeDistribution memory) {
    return _prizeDistributionsRingBuffer[_prizeDistributionsRingBufferData.getIndex(drawId)];
  }

  /**
    * @notice Set newest PrizeDistributionHistory in ring buffer storage.
    * @param _drawId       Draw.drawId
    * @param _prizeDistribution PrizeDistributionHistory struct
   */
  function _pushPrizeDistribution(uint32 _drawId, DrawLib.PrizeDistribution calldata _prizeDistribution) internal returns (bool) {
    require(_drawId > 0, "DrawCalc/draw-id-gt-0");
    require(_prizeDistribution.bitRangeSize <= 256 / _prizeDistribution.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_prizeDistribution.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
    require(_prizeDistribution.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");

    // ensure that the distributions are not gt 100%
    uint256 sumTotalDistributions = 0;
    uint256 nonZeroDistributions = 0;
    uint256 distributionsLength = _prizeDistribution.distributions.length;

    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _prizeDistribution.distributions[index];
      if(_prizeDistribution.distributions[index] > 0){
        nonZeroDistributions++;
      }
    }

    // Each distribution amount stored as uint32 - summed can't exceed 1e9
    require(sumTotalDistributions <= DISTRIBUTION_CEILING, "DrawCalc/distributions-gt-100%");

    require(_prizeDistribution.matchCardinality >= nonZeroDistributions, "DrawCalc/matchCardinality-gte-distributions");

    DrawRingBufferLib.Buffer memory _prizeDistributionsRingBufferData = prizeDistributionsRingBufferData;
    _prizeDistributionsRingBuffer[_prizeDistributionsRingBufferData.nextIndex] = _prizeDistribution;
    prizeDistributionsRingBufferData = prizeDistributionsRingBufferData.push(_drawId);

    emit PrizeDistributionsSet(_drawId, _prizeDistribution);

    return true;
  }
}
