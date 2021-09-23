// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../libraries/TwabLibrary.sol";

interface ITicket {

  event Delegated(
    address indexed user,
    address indexed delegate
  );

  /// @notice Emitted when ticket is initialized.
  /// @param name Ticket name (eg: PoolTogether Dai Ticket (Compound)).
  /// @param symbol Ticket symbol (eg: PcDAI).
  /// @param decimals Ticket decimals.
  /// @param controller Token controller address.
  event TicketInitialized(
    string name,
    string symbol,
    uint8 decimals,
    address controller
  );

  /// @notice Emitted when a new TWAB has been recorded.
  /// @param ticketHolder The Ticket holder address.
  /// @param user The recipient of the ticket power (may be the same as the ticketHolder)
  /// @param newTwab Updated TWAB of a ticket holder after a successful TWAB recording.
  event NewUserTwab(
    address indexed ticketHolder,
    address indexed user,
    ObservationLib.Observation newTwab
  );

  /// @notice Emitted when a new total supply TWAB has been recorded.
  /// @param newTotalSupplyTwab Updated TWAB of tickets total supply after a successful total supply TWAB recording.
  event NewTotalSupplyTwab(
    ObservationLib.Observation newTotalSupplyTwab
  );
  
  function getBalanceAt(address user, uint256 timestamp) external view returns(uint256);
  function getBalancesAt(address user, uint32[] calldata timestamp) external view returns(uint256[] memory);
  function getAverageBalanceBetween(address user, uint256 startTime, uint256 endTime) external view returns (uint256);
  function getAverageBalancesBetween(address user, uint32[] calldata startTimes, uint32[] calldata endTimes) external view returns (uint256[] memory);
  function getTotalSupply(uint32 timestamp) external view returns(uint256);
  function getTotalSupplies(uint32[] calldata timestamp) external view returns(uint256[] memory);
  function getAverageTotalSuppliesBetween(uint32[] calldata startTimes, uint32[] calldata endTimes) external view returns(uint256[] memory);
}
