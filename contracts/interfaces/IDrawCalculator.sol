// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ITicket.sol";
import "../DrawPrizes.sol";
import "../libraries/DrawLib.sol";

interface IDrawCalculator {

  ///@notice Emitted when the contract is initialized
  event Deployed(ITicket indexed ticket);

  ///@notice Emitted when the claimableDraw is set/updated
  event DrawPrizesSet(DrawPrizes indexed claimableDraw);

  function calculate(address user, uint32[] calldata drawIds, bytes calldata data)
    external view returns (uint256[] memory);
}
