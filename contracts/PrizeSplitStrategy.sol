// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "./interfaces/IPrizePool.sol";
import "./prize-strategy/PrizeSplit.sol";

/**
  * @title  PoolTogether V4 PrizeSplitStrategy
  * @author PoolTogether Inc Team
  * @notice Captures PrizePool interest for PrizeReserve and additional PrizeSplit recipients.
            The PrizeSplitStrategy will have at minimum a single PrizeSplit with 100% of the captured
            interest transfered to the PrizeReserve. Additional PrizeSplits can be added, depending on
            the deployers requirements (i.e. percentage to charity). In contrast to previous PoolTogether
            iterations, interest can be captured independent of a new Draw. Ideally (to save gas) interest 
            is only captured when also distributing the captured prize(s) to applicable ClaimbableDraw(s).   
*/
contract PrizeSplitStrategy is PrizeSplit {

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

  /* ============ Deploy ============ */

  /**
    * @notice Deploy the PrizeSplitStrategy smart contract.
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
    * @dev    Can be executed by any wallet at any time. Optimal executation (minimal wasted gas) 
              is coordination when pushing Draw(s) to DrawHistory to cover upcoming prize distribution.
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
