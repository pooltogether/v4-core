// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface IDrawHistory {
  function getDraws(uint224[] drawIds) external returns (DrawLib.Draw[] memory);
  function getDraw(uint224 drawId) external returns (DrawLib.Draw memory);
  function pushDraw(DrawLib.Draw memory draw) external returns(uint224 drawId);
  function setDraw(DrawLib.Draw memory draw) external returns(uint224 drawId); // maybe return drawIndex
}