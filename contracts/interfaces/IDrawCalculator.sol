// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ITicket.sol";
import "../ClaimableDraw.sol";
import "../libraries/DrawLib.sol";

interface IDrawCalculator {
  
  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(uint32 indexed drawId, DrawLib.DrawSettings drawSettings);

  ///@notice Emitted when the contract is initialized
  event Initialized(ITicket indexed ticket);

  ///@notice Emitted when the claimableDraw is set/updated
  event ClaimableDrawSet(ClaimableDraw indexed claimableDraw);

    ///@notice Emitted when the timestamp cutoff times are set/updated
  event TimestampCutoffTimes(DrawLib.DrawCalculatorCutoffTimes cutoffTimes);
  
  function calculate(address user, DrawLib.Draw[] calldata draws, bytes calldata pickIndicesForDraws)
    external view returns (uint96[] memory);
}