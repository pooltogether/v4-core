pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";
import "./interfaces/IOracleTimelock.sol";
import "./libraries/OracleTimelockLib.sol";

/**
  * @title  PoolTogether V4 OracleTimelock
  * @author PoolTogether Inc Team
  * @notice OracleTimelock(s) acts as an intermediary between multiple V4 smart contracts.
            The OracleTimelock is responsible for pushing Draws to a DrawHistory and routing
            claim requests from a ClaimableDraw to a DrawCalculator. The primary objective is
            to  include a "cooldown" period for all new Draws. Allowing the correction of a
            malicously set Draw in the unfortunate event an Owner is compromised.
*/
contract OracleTimelock is  IOracleTimelock, IDrawCalculator, OwnerOrManager {

  /* ============ Global Variables ============ */

  /// @notice Seconds required to elapse before newest Draw is avaible.
  uint32 internal timelockDuration;
  
  /// @notice Internal DrawHistory reference.
  IDrawHistory internal immutable drawHistory;
  
  /// @notice Internal DrawCalculator reference.
  IDrawCalculator internal immutable calculator;
  
  /// @notice Internal TsunamiDrawSettingsHistory reference.
  TsunamiDrawSettingsHistory internal immutable tsunamiDrawSettingsHistory;

  /// @notice Internal Timelock struct reference.
  OracleTimelockLib.Timelock internal timelock;

  /* ============ Deploy ============ */

  /**
    * @notice Initialize OracleTimelock smart contract.
    * @param _tsunamiDrawSettingsHistory TsunamiDrawSettingsHistory address
    * @param _drawHistory                DrawHistory address
    * @param _calculator                 DrawCalculator address
    * @param _timelockDuration           Elapsed seconds before new Draw is available
  */
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

  /**
    * @notice Routes claim/calculate requests between ClaimableDraw and DrawCalculator.
    * @dev    Will enforce a "cooldown period between when a Draw is pushed and when users can start to claim prizes. 
    * @param user    User address
    * @param drawIds Draw.drawId
    * @param data    Encoded pick indices
    * @return Prizes awardable array
  */
  function calculate(address user, uint32[] calldata drawIds, bytes calldata data) external override view returns (uint256[] memory) {
    OracleTimelockLib.Timelock memory timelock = timelock;
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
  function push(DrawLib.Draw memory _draw, DrawLib.TsunamiDrawSettings memory _drawSetting) external override onlyManagerOrOwner {
    requireTimelockElapsed();
    drawHistory.pushDraw(_draw);
    tsunamiDrawSettingsHistory.pushDrawSettings(_draw.drawId, _drawSetting);
    timelock = OracleTimelockLib.Timelock({
      drawId: _draw.drawId,
      timestamp: uint128(block.timestamp)
    });
  }

  /**
    * @notice Require the timelock "cooldown" period has elapsed
  */
  function requireTimelockElapsed() internal view {
    require(_timelockHasElapsed(timelock), "OM/timelock-not-expired");
  }

  /**
    * @notice Read internal TsunamiDrawSettingsHistory variable.
    * @return TsunamiDrawSettingsHistory
  */
  function getTsunamiDrawSettingsHistory() external override view returns (TsunamiDrawSettingsHistory) {
    return tsunamiDrawSettingsHistory;
  }

  /**
    * @notice Read internal DrawHistory variable.
    * @return IDrawHistory
  */
  function getDrawHistory() external override view returns (IDrawHistory) {
    return drawHistory;
  }

  /**
    * @notice Read internal DrawCalculator variable.
    * @return IDrawCalculator
  */
  function getDrawCalculator() external override view returns (IDrawCalculator) {
    return calculator;
  }

  /**
    * @notice Read internal Timelock struct.
    * @return Timelock
  */
  function getTimelock() external override view returns (OracleTimelockLib.Timelock memory) {
    return timelock;
  }

  /**
    * @notice Read internal timelockDuration variable.
    * @return Seconds to pass before Draw is valid.
  */
  function getTimelockDuration() external override view returns (uint32) {
    return timelockDuration;
  }

  /**
    * @notice Set new Timelock struct.
    * @dev    Set new Timelock struct and emit TimelockSet event.
  */
  function setTimelock(OracleTimelockLib.Timelock memory _timelock) external override onlyOwner {
    timelock = _timelock;

    emit TimelockSet(_timelock);
  }

  /**
    * @notice Set new timelockDuration.
    * @dev    Set new timelockDuration and emit TimelockDurationSet event.
  */
  function setTimelockDuration(uint32 _timelockDuration) external override onlyOwner {
    timelockDuration = _timelockDuration;

    emit TimelockDurationSet(_timelockDuration);
  }

  /**
    * @notice Returns bool for timelockDuration elapsing. 
    * @return True if timelockDuration, since last timelock has elapsed, false otherwse.
  */
  function hasElapsed() external override view returns (bool) {
    return _timelockHasElapsed(timelock);
  }

  /**
    * @notice Read global DrawCalculator variable.
    * @return IDrawCalculator
  */
  function _timelockHasElapsed(OracleTimelockLib.Timelock memory timelock) internal view returns (bool) {
    // If the timelock hasn't been initialized, then it's elapsed
    if (timelock.timestamp == 0) { return true; }
    // otherwise if the timelock has expired, we're good.
    return (block.timestamp > timelock.timestamp + timelockDuration);
  }

}