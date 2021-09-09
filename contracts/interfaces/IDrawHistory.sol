// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface IDrawHistory {
  
  /**
    * @notice Emit when a new draw has been created.
    * @param drawIndex    Draw index in the draws array
    * @param drawId       Draw id
    * @param timestamp    Epoch timestamp when the draw is created.
    * @param winningRandomNumber Randomly generated number used to calculate draw winning numbers
  */
  event DrawSet (
    uint256 drawIndex,
    uint32 drawId,
    uint32 timestamp,
    uint256 winningRandomNumber
  );

  function drawIdToDrawIndex(uint32 drawId) external view returns(uint32);
  function getDraws(uint32[] calldata drawIds) external view returns (DrawLib.Draw[] memory);
  function getDraw(uint32 drawId) external view returns (DrawLib.Draw memory);
  function pushDraw(DrawLib.Draw calldata draw) external returns(uint32);
  function setDraw(uint256 drawIndex, DrawLib.Draw calldata draw) external returns(uint32); // maybe return drawIndex
}