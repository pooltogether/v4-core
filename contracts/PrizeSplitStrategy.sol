// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./interfaces/IPrizePool.sol";
import "./prize-strategy/PrizeSplit.sol";

contract PrizeSplitStrategy is PrizeSplit {

  /* ============ Variables ============ */

  /**
    * @notice Linked PrizePool smart contract responsible for awarding tokens.
  */
  IPrizePool public prizePool;

  /* ============ Events ============ */

  /**
    * @notice Emit when a strategy captures award amount from PrizePool.
    * @param totalPrizeCaptured  Total prize captured from PrizePool
  */
  event Distributed(
    uint256 totalPrizeCaptured
  );

  /**
    * @notice Emit when an individual prize split is awarded.
    * @param user          User address being awarded
    * @param prizeAwarded  Token prize amount
    * @param token         Token awarded address
  */
  event PrizeSplitAwarded(
    address indexed user,
    uint256 prizeAwarded,
    IControlledToken indexed token
  );

  /* ============ Initialize ============ */

  /**
    * @notice Initialize the PrizeSplitStrategy smart contract.
    * @param _prizePool PrizePool contract address
  */
  constructor(
    IPrizePool _prizePool
  ) {
    require(address(_prizePool) != address(0), "PrizeSplitStrategy/prize-pool-not-zero-address");
    prizePool = _prizePool;
  }

  /* ============ External Functions ============ */

  /**
    * @notice Capture the award balance and distribute to prize splits.
    * @dev    Capture the award balance and award tokens using the linked PrizePool.
    * @return Total prize amount captured via prizePool.captureAwardBalance()
  */
  function distribute() external returns (uint256) {
    uint256 prize = prizePool.captureAwardBalance();
    _distributePrizeSplits(prize);
    emit Distributed(prize);
    return prize;
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Award ticket tokens to prize split recipient.
    * @dev Award ticket tokens to prize split recipient via the linked PrizePool contract.
    * @param _to Recipient of minted tokens.
    * @param _amount Amount of minted tokens.
  */
  function _awardPrizeSplitAmount(address _to, uint256 _amount) override internal {
    IControlledToken _ticket = prizePool.ticket();
    prizePool.award(_to, _amount);
    emit PrizeSplitAwarded(_to, _amount, _ticket);
  }

}
