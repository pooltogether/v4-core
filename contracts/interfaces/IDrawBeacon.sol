// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "../DrawHistory.sol";
import "../libraries/DrawLib.sol";

interface IDrawBeacon {
  function setDrawHistory(DrawHistory newDrawHistory) external virtual returns (DrawHistory);
}