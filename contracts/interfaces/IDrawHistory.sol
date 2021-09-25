// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface IDrawHistory {

  /**
    * @notice Emit when a new draw has been created.
    * @param drawId Draw id
    * @param draw The Draw struct
  */
  event DrawSet (
    uint32 indexed drawId,
    DrawLib.Draw draw
  );

  function getDraws(uint32[] calldata drawIds) external view returns (DrawLib.Draw[] memory);
  function getDraw(uint32 drawId) external view returns (DrawLib.Draw memory);
  function pushDraw(DrawLib.Draw calldata draw) external returns(uint32);
  function setDraw(DrawLib.Draw calldata draw) external returns(uint32); // maybe return drawIndex
}