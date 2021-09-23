// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBuffer.sol";
import "./interfaces/ITsunamiDrawSettingsHistory.sol";

/**
  * @title  PoolTogether V4 TsunamiDrawSettingsHistory
  * @author PoolTogether Inc Team
  * @notice The TsunamiDrawSettingsHistory stores individual DrawSettings for each Draw.drawId.
            DrawSettings parameters like cardinality, bitRange, distributions, number of picks
            and prize. The settings determine the specific distribution model for each individual 
            draw. Storage of the DrawSetting(s) is handled by ring buffer with a max cardinality
            of 256 or roughly 5 years of history with a weekly draw cadence.
*/
contract TsunamiDrawSettingsHistory is ITsunamiDrawSettingsHistory, Manageable {
  using DrawRingBuffer for DrawRingBuffer.Buffer;

  uint256 internal constant MAX_CARDINALITY = 256;

  event Deployed(uint8 cardinality);

  /// @notice DrawSettings ring buffer history.
  DrawLib.TsunamiDrawSettings[MAX_CARDINALITY] internal _drawSettingsRingBuffer;

  /// @notice Ring buffer data (nextIndex, lastDrawId, cardinality)
  DrawRingBuffer.Buffer internal drawSettingsRingBufferData;

  /* ============ Constructor ============ */

  /**
    * @notice Constructor for TsunamiDrawSettingsHistory
    * @param _owner Address of the TsunamiDrawSettingsHistory owner
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

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function getCardinality() external override view returns(uint256) {
    return MAX_CARDINALITY;
  }

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function getDrawSetting(uint32 _drawId) external override view returns(DrawLib.TsunamiDrawSettings memory) {
    return _getDrawSettings(drawSettingsRingBufferData, _drawId);
  }

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function getDrawSettings(uint32[] calldata _drawIds) external override view returns(DrawLib.TsunamiDrawSettings[] memory) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    DrawLib.TsunamiDrawSettings[] memory _drawSettings = new DrawLib.TsunamiDrawSettings[](_drawIds.length);
    for (uint256 i = 0; i < _drawIds.length; i++) {
      _drawSettings[i] = _getDrawSettings(buffer, _drawIds[i]);
    }
    return _drawSettings;
  }

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function getNewestDrawSettings() external override view returns (DrawLib.TsunamiDrawSettings memory drawSettings, uint32 drawId) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    return (_drawSettingsRingBuffer[buffer.getIndex(buffer.lastDrawId)], buffer.lastDrawId);
  }

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function getOldestDrawSettings() external override view returns (DrawLib.TsunamiDrawSettings memory drawSettings, uint32 drawId) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    drawSettings = _drawSettingsRingBuffer[buffer.nextIndex];
    
    // IF the next DrawSettings.bitRangeSize == 0 the ring buffer HAS NOT looped around.
    // The DrawSettings at index 0 IS by defaut the oldest drawSettings.
    if (drawSettings.bitRangeSize == 0 && buffer.lastDrawId > 0) {
      drawSettings = _drawSettingsRingBuffer[0];
      drawId = (buffer.lastDrawId + 1) - buffer.nextIndex; // 2 + 1 - 2 = 1 | [1,2,0]
    } else if (buffer.lastDrawId == 0) {
      drawId = 0; // return 0 to indicate no drawSettings ring buffer history
    } else {
      // Calculates the Draw.drawID using the ring buffer length and SEQUENTIAL id(s)
      // Sequential "guaranteedness" is handled in DrawRingBufferLib.push()
      drawId = (buffer.lastDrawId + 1) - buffer.cardinality; // 4 + 1 - 3 = 2 | [4,2,3]
    }

    // automatic return with named "returns" values
  }

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawSettings calldata _drawSettings) external override onlyManagerOrOwner returns (bool) {
    return _pushDrawSettings(_drawId, _drawSettings);
  }

  /// @inheritdoc ITsunamiDrawSettingsHistory
  function setDrawSetting(uint32 _drawId, DrawLib.TsunamiDrawSettings calldata _drawSettings) external override onlyOwner returns (uint32) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBufferData;
    uint32 index = buffer.getIndex(_drawId);
    _drawSettingsRingBuffer[index] = _drawSettings;
    emit DrawSettingsSet(_drawId, _drawSettings);
    return _drawId;
  }


  /* ============ Internal Functions ============ */
  
  /**
    * @notice Gets the TsunamiDrawSettingsHistorySettings for a Draw.drawID
    * @param _drawSettingsRingBufferData DrawRingBuffer.Buffer
    * @param drawId Draw.drawId
   */
  function _getDrawSettings(
    DrawRingBuffer.Buffer memory _drawSettingsRingBufferData,
    uint32 drawId
  ) internal view returns (DrawLib.TsunamiDrawSettings memory) {
    return _drawSettingsRingBuffer[_drawSettingsRingBufferData.getIndex(drawId)];
  }

  /**
    * @notice Set newest TsunamiDrawSettingsHistorySettings in ring buffer storage.
    * @param _drawId       Draw.drawId
    * @param _drawSettings TsunamiDrawSettingsHistorySettings struct
   */
  function _pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawSettings calldata _drawSettings) internal returns (bool) {
    uint256 distributionsLength = _drawSettings.distributions.length;

    require(_drawId > 0, "DrawCalc/draw-id-gt-0");
    require(_drawSettings.matchCardinality >= distributionsLength, "DrawCalc/matchCardinality-gte-distributions");
    require(_drawSettings.bitRangeSize <= 256 / _drawSettings.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_drawSettings.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
    require(_drawSettings.numberOfPicks > 0, "DrawCalc/numberOfPicks-gt-0");
    require(_drawSettings.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");

    // ensure that the distributions are not gt 100%
    uint256 sumTotalDistributions = 0;
    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    }

    require(sumTotalDistributions <= 1e9, "DrawCalc/distributions-gt-100%");

    DrawRingBuffer.Buffer memory _drawSettingsRingBufferData = drawSettingsRingBufferData;
    _drawSettingsRingBuffer[_drawSettingsRingBufferData.nextIndex] = _drawSettings;
    drawSettingsRingBufferData = drawSettingsRingBufferData.push(_drawId);

    emit DrawSettingsSet(_drawId, _drawSettings);

    return true;
  }
}
