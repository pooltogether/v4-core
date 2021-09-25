// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBuffer.sol";
import "./interfaces/IPrizeDistributionHistory.sol";

/**
  * @title  PoolTogether V4 PrizeDistributionHistory
  * @author PoolTogether Inc Team
  * @notice The PrizeDistributionHistory stores individual DrawSettings for each Draw.drawId.
            DrawSettings parameters like cardinality, bitRange, distributions, number of picks
            and prize. The settings determine the specific distribution model for each individual 
            draw. Storage of the DrawSetting(s) is handled by ring buffer with a max cardinality
            of 256 or roughly 5 years of history with a weekly draw cadence.
*/
contract PrizeDistributionHistory is IPrizeDistributionHistory, Manageable {
  using DrawRingBuffer for DrawRingBuffer.Buffer;

  uint256 internal constant MAX_CARDINALITY = 256;

  uint256 internal constant DISTRIUBTION_CEILING = 1e9;
  event Deployed(uint8 cardinality);

  /// @notice DrawSettings ring buffer history.
  DrawLib.PrizeDistribution[MAX_CARDINALITY] internal _drawSettingsRingBuffer;

  /// @notice Ring buffer data (nextIndex, lastDrawId, cardinality)
  DrawRingBuffer.Buffer internal drawSettingsRingBufferData;

  /* ============ Constructor ============ */

  /**
    * @notice Constructor for PrizeDistributionHistory
    * @param _owner Address of the PrizeDistributionHistory owner
    * @param _cardinality Cardinality of the `drawSettingsRingBufferData`
   */
  constructor(
    address _owner,
    uint8 _cardinality
  ) Ownable(_owner) {
    drawSettingsRingBufferData.cardinality = _cardinality;
    emit Deployed(_cardinality);
  }

  /* ============ External Functions ============ */

  /// @inheritdoc IPrizeDistributionHistory
  function getDrawSetting(uint32 _drawId) external override view returns(DrawLib.PrizeDistribution memory) {
    return _getDrawSettings(drawSettingsRingBufferData, _drawId);
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getDrawSettings(uint32[] calldata _drawIds) external override view returns(DrawLib.PrizeDistribution[] memory) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    DrawLib.PrizeDistribution[] memory _drawSettings = new DrawLib.PrizeDistribution[](_drawIds.length);
    for (uint256 i = 0; i < _drawIds.length; i++) {
      _drawSettings[i] = _getDrawSettings(buffer, _drawIds[i]);
    }
    return _drawSettings;
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getNewestDrawSettings() external override view returns (DrawLib.PrizeDistribution memory drawSettings, uint32 drawId) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    return (_drawSettingsRingBuffer[buffer.getIndex(buffer.lastDrawId)], buffer.lastDrawId);
  }

  /// @inheritdoc IPrizeDistributionHistory
  function getOldestDrawSettings() external override view returns (DrawLib.PrizeDistribution memory drawSettings, uint32 drawId) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    drawSettings = _drawSettingsRingBuffer[buffer.nextIndex];
    
    // IF the next DrawSettings.bitRangeSize == 0 the ring buffer HAS NOT looped around.
    // The DrawSettings at index 0 IS by defaut the oldest drawSettings.
    if (buffer.lastDrawId == 0) {
      drawId = 0; // return 0 to indicate no drawSettings ring buffer history
    } else if (drawSettings.bitRangeSize == 0) {
      drawSettings = _drawSettingsRingBuffer[0];
      drawId = (buffer.lastDrawId + 1) - buffer.nextIndex; // 2 + 1 - 2 = 1 | [1,2,0]
    } else {
      // Calculates the Draw.drawID using the ring buffer length and SEQUENTIAL id(s)
      // Sequential "guaranteedness" is handled in DrawRingBufferLib.push()
      drawId = (buffer.lastDrawId + 1) - buffer.cardinality; // 4 + 1 - 3 = 2 | [4,2,3]
    }

    // automatic return with named "returns" values
  }

  /// @inheritdoc IPrizeDistributionHistory
  function pushDrawSettings(uint32 _drawId, DrawLib.PrizeDistribution calldata _drawSettings) external override onlyManagerOrOwner returns (bool) {
    return _pushDrawSettings(_drawId, _drawSettings);
  }

  /// @inheritdoc IPrizeDistributionHistory
  function setDrawSetting(uint32 _drawId, DrawLib.PrizeDistribution calldata _drawSettings) external override onlyOwner returns (uint32) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    uint32 index = buffer.getIndex(_drawId);
    _drawSettingsRingBuffer[index] = _drawSettings;
    emit DrawSettingsSet(_drawId, _drawSettings);
    return _drawId;
  }


  /* ============ Internal Functions ============ */
  
  /**
    * @notice Gets the PrizeDistributionHistorySettings for a Draw.drawID
    * @param _drawSettingsRingBufferData DrawRingBuffer.Buffer
    * @param drawId Draw.drawId
   */
  function _getDrawSettings(
    DrawRingBuffer.Buffer memory _drawSettingsRingBufferData,
    uint32 drawId
  ) internal view returns (DrawLib.PrizeDistribution memory) {
    return _drawSettingsRingBuffer[_drawSettingsRingBufferData.getIndex(drawId)];
  }

  /**
    * @notice Set newest PrizeDistributionHistorySettings in ring buffer storage.
    * @param _drawId       Draw.drawId
    * @param _drawSettings PrizeDistributionHistorySettings struct
   */
  function _pushDrawSettings(uint32 _drawId, DrawLib.PrizeDistribution calldata _drawSettings) internal returns (bool) {
    uint256 distributionsLength = _drawSettings.distributions.length;

    require(_drawId > 0, "DrawCalc/draw-id-gt-0");
    require(_drawSettings.matchCardinality >= distributionsLength, "DrawCalc/matchCardinality-gte-distributions");
    require(_drawSettings.bitRangeSize <= 256 / _drawSettings.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_drawSettings.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
    require(_drawSettings.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");

    // ensure that the distributions are not gt 100%
    uint256 sumTotalDistributions = 0;
    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    }

    // Each distribution amount stored as uint32 - summed can't exceed 1e9
    require(sumTotalDistributions <= DISTRIUBTION_CEILING, "DrawCalc/distributions-gt-100%");

    DrawRingBuffer.Buffer memory _drawSettingsRingBufferData = drawSettingsRingBufferData;
    _drawSettingsRingBuffer[_drawSettingsRingBufferData.nextIndex] = _drawSettings;
    drawSettingsRingBufferData = drawSettingsRingBufferData.push(_drawId);

    emit DrawSettingsSet(_drawId, _drawSettings);

    return true;
  }
}
