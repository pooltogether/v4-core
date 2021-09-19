// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBuffer.sol";

import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";

///@title TsunamiDrawSettingsHistory
contract TsunamiDrawSettingsHistory is OwnerOrManager {
  using DrawRingBuffer for DrawRingBuffer.Buffer;
  
  uint256 constant MAX_CARDINALITY = 256;

  event Deployed(uint8 cardinality);

  /// @notice The stored history of draw settings.  Stored as ring buffer.
  DrawLib.TsunamiDrawSettingsHistorySettings[MAX_CARDINALITY] drawSettings;

  DrawRingBuffer.Buffer internal drawSettingsRingBuffer;

  /* ============ Constructor ============ */

  ///@notice Constructor for TsunamiDrawSettingsHistory
  ///@param _ticket Ticket associated with this DrawCalculator
  ///@param _drawSettingsManager Address of the DrawSettingsManager. Can be different from the contract owner.
  constructor(uint8 _cardinality) {
    drawSettingsRingBuffer.cardinality = _cardinality;

    emit Deployed(_ticket);
  }

  ///@notice Sets TsunamiDrawSettingsHistorySettings for a draw id. only callable by the owner or manager
  ///@param _drawId The id of the Draw
  ///@param _drawSettings The TsunamiDrawSettingsHistorySettings to set
  function pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawSettingsHistorySettings calldata _drawSettings) external onlyManagerOrOwner
    returns (bool success)
  {
    return _pushDrawSettings(_drawId, _drawSettings);
  }

  ///@notice Gets the TsunamiDrawSettingsHistorySettings for a draw id
  ///@param _drawId The id of the Draw
  function getDrawSettings(uint32 _drawId) external view returns(DrawLib.TsunamiDrawSettingsHistorySettings memory)
  {
    return _getDrawSettings(drawSettingsRingBuffer, _drawId);
  }

  ///@notice Gets the TsunamiDrawSettingsHistorySettings for a draw id
  ///@param _drawId The id of the Draw
  function getDrawSettings(uint32[] _drawIds) external view returns(DrawLib.TsunamiDrawSettingsHistorySettings[] memory)
  {
    DrawRingBuffer.Buffer memory buffer = drawSettingsRingBuffer;
    DrawLib.TsunamiDrawSettingsHistorySettings[] memory _drawSettings = new DrawLib.TsunamiDrawSettingsHistorySettings[](_drawIds.length)
    for (uint256 i = 0; i < _drawIds.length; i++) {
      _drawSettings[i] = _getDrawSettings(buffer, _drawIds[i]);
    }
  }

  ///@notice Set the DrawCalculators TsunamiDrawSettingsHistorySettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawId The id of the Draw
  ///@param _drawSettings TsunamiDrawSettingsHistorySettings struct to set
  function _pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawSettingsHistorySettings calldata _drawSettings) internal
    returns (bool)
  {
    uint256 distributionsLength = _drawSettings.distributions.length;

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
  ) internal view returns (DrawLib.TsunamiDrawSettingsHistorySettings memory) {
    return drawSettings[_drawSettingsRingBuffer.getIndex(drawId)];
  }
}
