// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IPrizePool.sol";
import "./prize-strategy/PrizeSplit.sol";

contract PrizeSplitStrategy is Initializable, PrizeSplit {

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
    address indexed token 
  );

  /* ============ Initialize ============ */

  /**
    * @notice Initialize the PrizeSplitStrategy smart contract.
    * @param _prizePool PrizePool contract address
  */
  function initialize (
    IPrizePool _prizePool
  ) external initializer {
    __Ownable_init();
    require(address(_prizePool) != address(0), "PrizeSplitStrategy/prize-pool-not-zero");
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
    * @notice Award ticket or sponsorship tokens to prize split recipient.
    * @dev Award ticket or sponsorship tokens to prize split recipient via the linked PrizePool contract.
    * @param user Recipient of minted tokens
    * @param amount Amount of minted tokens
    * @param tokenIndex Index (0 or 1) of a token in the prizePool.tokens mapping
  */
  function _awardPrizeSplitAmount(address user, uint256 amount, uint8 tokenIndex) override internal {
    IControlledToken _token = prizePool.tokenAtIndex(tokenIndex);
    prizePool.award(user, amount, address(_token));
    emit PrizeSplitAwarded(user, amount, address(_token));
  }

}
