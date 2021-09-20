// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface ITsunamiDrawSettingsHistory {

  /**
    * @notice Emit when a new draw has been created.
    * @param drawId       Draw id
    * @param timestamp    Epoch timestamp when the draw is created.
    * @param winningRandomNumber Randomly generated number used to calculate draw winning numbers
  */
  event DrawSet (
    uint32 drawId,
    uint32 timestamp,
    uint256 winningRandomNumber
  );

  function getDrawSettings(uint32[] calldata drawIds) external view returns (DrawLib.TsunamiDrawSettings[] memory);
  function getDrawSetting(uint32 drawId) external view returns (DrawLib.TsunamiDrawSettings memory);
  function pushDrawSettings(uint32 drawId, DrawLib.TsunamiDrawSettings calldata draw) external returns(bool);
  function setDrawSetting(uint32 drawId, DrawLib.TsunamiDrawSettings calldata draw) external returns(uint32); // maybe return drawIndex
  function getNewestDrawSettings() external view returns (DrawLib.TsunamiDrawSettings memory);
  function getOldestDrawSettings() external view returns (DrawLib.TsunamiDrawSettings memory);
}