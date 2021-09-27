// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "../libraries/TwabLib.sol";
interface ITicket {

  /**  
    * @notice A struct containing details for an Account
    * @param balance The current balance for an Account
    * @param nextTwabIndex The next available index to store a new twab
    * @param cardinality The number of recorded twabs (plus one!)
  */
  struct AccountDetails {
    uint224 balance;
    uint16 nextTwabIndex;
    uint16 cardinality;
  }

  /**  
    * @notice Combines account details with their twab history
    * @param details The account details
    * @param twabs The history of twabs for this account
  */
  struct Account {
    AccountDetails details;
    ObservationLib.Observation[65535] twabs;
  }

  event Delegated(
    address indexed user,
    address indexed delegate
  );

  /** 
    * @notice Emitted when ticket is initialized.
    * @param name Ticket name (eg: PoolTogether Dai Ticket (Compound)).
    * @param symbol Ticket symbol (eg: PcDAI).
    * @param decimals Ticket decimals.
    * @param controller Token controller address.
  */
  event TicketInitialized(
    string name,
    string symbol,
    uint8 decimals,
    address controller
  );

  /** 
    * @notice Emitted when a new TWAB has been recorded.
    * @param ticketHolder The Ticket holder address.
    * @param user The recipient of the ticket power (may be the same as the ticketHolder)
    * @param newTwab Updated TWAB of a ticket holder after a successful TWAB recording.
  */
  event NewUserTwab(
    address indexed ticketHolder,
    address indexed user,
    ObservationLib.Observation newTwab
  );

  /** 
    * @notice Emitted when a new total supply TWAB has been recorded.
    * @param newTotalSupplyTwab Updated TWAB of tickets total supply after a successful total supply TWAB recording.
  */
  event NewTotalSupplyTwab(
    ObservationLib.Observation newTotalSupplyTwab
  );

   /** 
    * @notice ADD DOCS
    * @param user Address
  */
  function delegateOf(address user) external view returns (address);

  /**
    * @notice Delegate time-weighted average balances to an alternative address.
    * @dev    Transfers (including mints) trigger the storage of a TWAB in delegatee(s) account, instead of the
              targetted sender and/or recipient address(s).
    * @dev    "to" reset the delegatee use zero address (0x000.000) 
    * @param  to Receipient of delegated TWAB
   */
  function delegate(address to) external virtual;
  
  /** 
    * @notice Gets a users twap context.  This is a struct with their balance, next twab index, and cardinality.
    * @param user The user for whom to fetch the TWAB context
    * @return The TWAB context, which includes { balance, nextTwabIndex, cardinality }
  */
  function getAccountDetails(address user) external view returns (TwabLib.AccountDetails memory);
  
  /** 
    * @notice Gets the TWAB at a specific index for a user.
    * @param user The user for whom to fetch the TWAB
    * @param index The index of the TWAB to fetch
    * @return The TWAB, which includes the twab amount and the timestamp.
  */
  function getTwab(address user, uint16 index) external view returns (ObservationLib.Observation memory);

  /** 
    * @notice Retrieves `_user` TWAB balance.
    * @param user Address of the user whose TWAB is being fetched.
    * @param timestamp Timestamp at which the reserved TWAB should be for.
  */
  function getBalanceAt(address user, uint256 timestamp) external view returns(uint256);

  /** 
    * @notice Retrieves `_user` TWAB balances.
    * @param user Address of the user whose TWABs are being fetched.
    * @param timestamps Timestamps at which the reserved TWABs should be for.
    * @return uint256[] `_user` TWAB balances.
  */
  function getBalancesAt(address user, uint32[] calldata timestamps) external view returns(uint256[] memory);

  /** 
    * @notice Calculates the average balance held by a user for given time frames.
    * @param user The user whose balance is checked
    * @param startTime The start time of the time frame.
    * @param endTime The end time of the time frame.
    * @return The average balance that the user held during the time frame.
  */
  function getAverageBalanceBetween(address user, uint256 startTime, uint256 endTime) external view returns (uint256);

  /** 
    * @notice Calculates the average balance held by a user for given time frames.
    * @param user The user whose balance is checked
    * @param startTimes The start time of the time frame.
    * @param endTimes The end time of the time frame.
    * @return The average balance that the user held during the time frame.
  */
  function getAverageBalancesBetween(address user, uint32[] calldata startTimes, uint32[] calldata endTimes) external view returns (uint256[] memory);

  /** 
    * @notice Calculates the average balance held by a user for given time frames.
    * @param timestamp Timestamp
    * @return The
  */
  function getTotalSupplyAt(uint32 timestamp) external view returns(uint256);

   /** 
    * @notice Calculates the average balance held by a user for given time frames.
    * @param timestamps Timestamp
    * @return The
  */
  function getTotalSuppliesAt(uint32[] calldata timestamps) external view returns(uint256[] memory);

  /** 
    * @notice Calculates the average total supply balance for a set of given time frames.
    * @param startTimes Array of start times
    * @param endTimes Array of end times
    * @return The average total supplies held during the time frame.
  */
  function getAverageTotalSuppliesBetween(uint32[] calldata startTimes, uint32[] calldata endTimes) external view returns(uint256[] memory);

}
