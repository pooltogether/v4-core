// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ITicket.sol";
import "../ClaimableDraw.sol";
import "../libraries/DrawLib.sol";

interface IDrawCalculator {

  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(uint32 indexed drawId, DrawLib.TsunamiDrawCalculatorSettings drawSettings);

  ///@notice Emitted when the contract is initialized
  event Deployed(ITicket indexed ticket);

  ///@notice Emitted when the claimableDraw is set/updated
  event ClaimableDrawSet(ClaimableDraw indexed claimableDraw);

  function calculate(address user, uint32[] calldata drawIds, bytes calldata data)
    external view returns (uint256[] memory);
}
