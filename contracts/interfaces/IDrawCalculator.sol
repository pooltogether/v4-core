// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ITicket.sol";
import "../ClaimableDraw.sol";
import "../libraries/DrawLib.sol";

interface IDrawCalculator {
  
  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(uint32 indexed drawId, DrawLib.DrawSettings _drawSettings);

  ///@notice Emitted when the contract is initialized
  event Initialized(ITicket indexed _ticket);

  ///@notice Emitted when the claimableDraw is set/updated
  event ClaimableDrawSet(ClaimableDraw indexed _claimableDraw);
  
  function calculate(address _user, DrawLib.Draw[] calldata _draws, bytes calldata _pickIndicesForDraws)
    external view returns (uint96[] memory);
}