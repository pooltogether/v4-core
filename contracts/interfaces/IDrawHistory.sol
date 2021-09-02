// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "../libraries/DrawLib.sol";

interface IDrawHistory {
  function getDraws(uint32[] calldata drawIds) external view returns (DrawLib.Draw[] memory);
  function getDraw(uint32 drawId) external view returns (DrawLib.Draw memory);
  function pushDraw(DrawLib.Draw calldata draw) external returns(uint32);
  function setDraw(uint256 drawIndex, DrawLib.Draw calldata draw) external returns(uint32); // maybe return drawIndex
}