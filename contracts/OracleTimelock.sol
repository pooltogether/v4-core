pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";

import "./TsunamiDrawSettingsHistory.sol";
import "./interfaces/IDrawCalculator.sol";
import "./interfaces/IDrawHistory.sol";

contract OracleTimelock is IDrawCalculator, OwnerOrManager {

  event TimelockSet(Timelock timelock);
  event TimelockDurationSet(uint32 duration);

  TsunamiDrawSettingsHistory public immutable tsunamiDrawSettingsHistory;
  IDrawHistory public immutable drawHistory;
  IDrawCalculator public immutable calculator;
  uint32 timelockDuration;

  struct Timelock {
    uint32 drawId;
    uint128 timestamp;
  }

  Timelock timelock;

  constructor (
    TsunamiDrawSettingsHistory _tsunamiDrawSettingsHistory,
    IDrawHistory _drawHistory,
    IDrawCalculator _calculator,
    uint32 _timelockDuration
  ) {
    tsunamiDrawSettingsHistory = _tsunamiDrawSettingsHistory;
    drawHistory = _drawHistory;
    calculator = _calculator;
    timelockDuration = _timelockDuration;
  }

  function calculate(address user, uint32[] calldata drawIds, bytes calldata data) external override view returns (uint256[] memory) {
    Timelock memory timelock = timelock;
    for (uint256 i = 0; i < drawIds.length; i++) {
      // if draw id matches timelock and not expired, revert
      if (drawIds[i] == timelock.drawId) {
        requireTimelockElapsed();
      }
    }
    return calculator.calculate(user, drawIds, data);
  }

  /**
    * @notice Push Draw onto draws ring buffer history.
    * @dev    Restricts new draws by forcing a push timelock.
    * @param _draw DrawLib.Draw
  */
  function push(DrawLib.Draw memory _draw, DrawLib.TsunamiDrawSettings memory _drawSetting) external onlyManagerOrOwner {
    requireTimelockElapsed();
    drawHistory.pushDraw(_draw);
    tsunamiDrawSettingsHistory.pushDrawSettings(_draw.drawId, _drawSetting);
    timelock = Timelock({
      drawId: _draw.drawId,
      timestamp: uint128(block.timestamp)
    });
  }

  function requireTimelockElapsed() internal view {
    require(_timelockHasElapsed(timelock), "OM/timelock-not-expired");
  }

  function getTsunamiDrawSettingsHistory() external view returns (TsunamiDrawSettingsHistory) {
    return tsunamiDrawSettingsHistory;
  }

  function getDrawHistory() external view returns (IDrawHistory) {
    return drawHistory;
  }

  function getDrawCalculator() external view returns (IDrawCalculator) {
    return calculator;
  }

  function getTimelock() external view returns (Timelock memory) {
    return timelock;
  }

  function getTimelockDuration() external view returns (uint32) {
    return timelockDuration;
  }

  function setTimelock(Timelock memory _timelock) external onlyOwner {
    timelock = _timelock;

    emit TimelockSet(_timelock);
  }

  function setTimelockDuration(uint32 _timelockDuration) external onlyOwner {
    timelockDuration = _timelockDuration;

    emit TimelockDurationSet(_timelockDuration);
  }

  function hasElapsed() external view returns (bool) {
    return _timelockHasElapsed(timelock);
  }

  function _timelockHasElapsed(Timelock memory timelock) internal view returns (bool) {
    // If the timelock hasn't been initialized, then it's elapsed
    if (timelock.timestamp == 0) { return true; }
    // otherwise if the timelock has expired, we're good.
    return (block.timestamp > timelock.timestamp + timelockDuration);
  }

}