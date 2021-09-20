// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./IOracleTimelock.sol";
import "./IDrawCalculator.sol";
import "./IDrawHistory.sol";
import "../TsunamiDrawSettingsHistory.sol";
import "../libraries/DrawLib.sol";
import "../libraries/OracleTimelockLib.sol";

interface IOracleTimelock {

  event TimelockSet(OracleTimelockLib.Timelock timelock);
  event TimelockDurationSet(uint32 duration);
  
  // function calculate(address user, uint32[] calldata drawIds, bytes calldata data) external override view returns (uint256[] memory);
  function push(DrawLib.Draw memory _draw, DrawLib.TsunamiDrawSettings memory _drawSetting) external;
  function getTsunamiDrawSettingsHistory() external view returns (TsunamiDrawSettingsHistory);
  function getDrawHistory() external view returns (IDrawHistory);
  function getDrawCalculator() external view returns (IDrawCalculator);
  function getTimelock() external view returns (OracleTimelockLib.Timelock memory);
  function getTimelockDuration() external view returns (uint32);
  function setTimelock(OracleTimelockLib.Timelock memory _timelock) external;
  function setTimelockDuration(uint32 _timelockDuration) external;
  function hasElapsed() external view returns (bool);
}
