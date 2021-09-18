// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IPrizePool.sol";
import "./prize-strategy/PrizeSplit.sol";

/**
  * @title  PoolTogether V4 PrizeSplitStrategy
  * @author PoolTogether Inc Team
  * @notice Captures PrizePool interest for PrizeReserve and secondary prize split recipients. 
*/
contract PrizeSplitStrategy is Initializable, PrizeSplit {

  /**
    * @notice PrizePool address
  */
  IPrizePool public prizePool;

  /* ============ Events ============ */

  /**
    * @notice Emit when a strategy captures award amount from PrizePool.
    * @param totalPrizeCaptured  Total prize captured from the PrizePool
  */
  event Distributed(
    uint256 totalPrizeCaptured
  );

  /**
    * @notice Emit when an individual prize split is awarded.
    * @param user          User address being awarded
    * @param prizeAwarded  Awarded prize amount
    * @param token         Token address
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
    * @dev    Can be executed by any wallet at any time. Optimal executation (minimal wasted gas) is before pushing a new Draw.
    * @return Prize captured from PrizePool
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
    * @dev    Award ticket or sponsorship tokens to prize split recipient via the linked PrizePool contract.
    * @param user       Recipient of prize split
    * @param amount     Prize split amount
    * @param tokenIndex Index (0 or 1) of a token in the prizePool.tokens mapping
  */
  function _awardPrizeSplitAmount(address user, uint256 amount, uint8 tokenIndex) override internal {
    IControlledToken _token = prizePool.tokenAtIndex(tokenIndex);
    prizePool.award(user, amount, _token);
    emit PrizeSplitAwarded(user, amount, _token);
  }

}
