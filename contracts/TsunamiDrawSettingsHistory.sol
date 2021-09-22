// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;
import "hardhat/console.sol";
import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBuffer.sol";
import "./interfaces/ITsunamiDrawSettingsHistory.sol";

///@title TsunamiDrawSettingsHistory
contract TsunamiDrawSettingsHistory is ITsunamiDrawSettingsHistory, Manageable {
  using DrawRingBuffer for DrawRingBuffer.Buffer;

  uint256 constant MAX_CARDINALITY = 256;

  event Deployed(uint8 cardinality);

  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(uint32 indexed drawId, DrawLib.TsunamiDrawSettings drawSettings);

  /// @notice The stored history of draw settings.  Stored as ring buffer.
  DrawLib.TsunamiDrawSettings[MAX_CARDINALITY] drawSettings;

  /// @notice Ring buffer data
  DrawRingBuffer.Buffer internal drawSettingsRingBuffer;

  /* ============ Constructor ============ */

  /// @notice Constructor for TsunamiDrawSettingsHistory
  /// @param _owner Address of the TsunamiDrawSettingsHistory owner
  /// @param _cardinality Cardinality of the `drawSettingsRingBuffer`

  constructor(
    address _owner,
    uint8 _cardinality
  ) Ownable(_owner) {
    drawSettingsRingBuffer.cardinality = _cardinality;

    emit Deployed(_cardinality);
  }

  ///@notice Sets TsunamiDrawSettingsHistorySettings for a draw id. only callable by the owner or manager
  ///@param _drawId The id of the Draw
  ///@param _drawSettings The TsunamiDrawSettingsHistorySettings to set
  function pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawSettings calldata _drawSettings) external override onlyManagerOrOwner
    returns (bool)
  {
    return _pushDrawSettings(_drawId, _drawSettings);
  }

  ///@notice Gets the TsunamiDrawSettingsHistorySettings for a draw id
  ///@param _drawId The id of the Draw
  function getDrawSetting(uint32 _drawId) external override view returns(DrawLib.TsunamiDrawSettings memory)
  {
    return _getDrawSettings(drawSettingsRingBuffer, _drawId);
  }

  ///@notice Gets the TsunamiDrawSettingsHistorySettings for a draw id
  ///@param _drawIds The draw ids to get the settings for
  function getDrawSettings(uint32[] calldata _drawIds) external override view returns(DrawLib.TsunamiDrawSettings[] memory)
  {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBuffer;
    DrawLib.TsunamiDrawSettings[] memory _drawSettings = new DrawLib.TsunamiDrawSettings[](_drawIds.length);
    for (uint256 i = 0; i < _drawIds.length; i++) {
      _drawSettings[i] = _getDrawSettings(buffer, _drawIds[i]);
    }
    return _drawSettings;
  }

  /**
    * @notice Read newest Draw from the draws ring buffer.
    * @dev    Uses the nextDrawIndex to calculate the most recently added Draw.
    * @return newestDrawSettings DrawLib.TsunamiDrawSettings
    * @return drawId Draw.drawId
  */
  function getNewestDrawSettings() external override view returns (DrawLib.TsunamiDrawSettings memory newestDrawSettings, uint32 drawId) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBuffer;
    return (drawSettings[buffer.getIndex(buffer.lastDrawId)], buffer.lastDrawId);
  }

  /**
    * @notice Read oldest Draw from the draws ring buffer.
    * @dev    Finds the oldest Draw by comparing and/or diffing totalDraws with the cardinality.
    * @return oldestDrawSettings DrawLib.TsunamiDrawSettings
    * @return drawId Draw.drawId
  */
  function getOldestDrawSettings() external override view returns (DrawLib.TsunamiDrawSettings memory oldestDrawSettings, uint32 drawId) {
    uint32 oldestDrawId;
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBuffer;
    // oldest draw should be next available index, otherwise it's at 0
    DrawLib.TsunamiDrawSettings memory drawSet = drawSettings[buffer.nextIndex];
    // estimate oldest drawId by using lastDrawId relative to ring buffer state.
    oldestDrawId = _calculateOldestDrawIdFromBuffer(drawSet.matchCardinality, buffer);
    // if draw is not init, then use draw at 0
    if (drawSet.matchCardinality == 0) {
      drawSet = drawSettings[0];
    } 
    return (drawSet,oldestDrawId);
  }

  /**
    * @notice Set existing Draw in draws ring buffer with new parameters.
    * @dev    Updating a Draw should be used sparingly and only in the event an incorrect Draw parameter has been stored.
    * @return Draw.drawId
  */
  function setDrawSetting(uint32 _drawId, DrawLib.TsunamiDrawSettings calldata _drawSettings) external override onlyOwner returns (uint32) {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBuffer;
    uint32 index = buffer.getIndex(_drawId);
    drawSettings[index] = _drawSettings;
    emit DrawSettingsSet(_drawId, _drawSettings);
    return _drawId;
  }

  ///@notice Set the DrawCalculators TsunamiDrawSettingsHistorySettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawId The id of the Draw
  ///@param _drawSettings TsunamiDrawSettingsHistorySettings struct to set
  function _pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawSettings calldata _drawSettings) internal
    returns (bool)
  {
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

    DrawRingBuffer.Buffer memory _drawSettingsRingBuffer = drawSettingsRingBuffer;
    drawSettings[_drawSettingsRingBuffer.nextIndex] = _drawSettings;
    drawSettingsRingBuffer = drawSettingsRingBuffer.push(_drawId);

    emit DrawSettingsSet(_drawId, _drawSettings);
    return true;
  }

  function _getDrawSettings(
    DrawRingBuffer.Buffer memory _drawSettingsRingBuffer,
    uint32 drawId
  ) internal view returns (DrawLib.TsunamiDrawSettings memory) {
    return drawSettings[_drawSettingsRingBuffer.getIndex(drawId)];
  }

  /**
    * @dev Calculate the oldest Draw ID using the ring buffer state.
    * @param _isWrapped Uses zero values to determine if ring buffer has looped
    * @param _buffer    Buffer state from DrawRingBuffer.Buffer)
    * @return Draw ID
   */
  function _calculateOldestDrawIdFromBuffer(uint8 _isWrapped, DrawRingBuffer.Buffer memory _buffer) internal view returns (uint32) {
    if(_buffer.lastDrawId == 0 && _buffer.nextIndex == 0) {
      return 0;
    } else if (_isWrapped == 0) {
      return (_buffer.lastDrawId - _buffer.nextIndex) + 1;
    } else {
      return (_buffer.lastDrawId - _buffer.cardinality) + 1;
    }
  }
}
