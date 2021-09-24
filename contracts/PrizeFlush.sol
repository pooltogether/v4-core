// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPrizeFlush.sol";

/**
  * @title  PoolTogether V4 Reserve
  * @author PoolTogether Inc Team
  * @notice The PrizeFlush is a helper library to facilate interest distribution. 
*/
contract PrizeFlush is IPrizeFlush {

  // IReserve internal reserve;
  // IStrategy internal strategy;

  /* ============ Events ============ */

  event Deployed(IReserve reserve, IStrategy strategy);

  /* ============ Constructor ============ */    

  constructor(IReserve _reserve, IStrategy _strategy) {
    // reserve = _reserve;
    // strategy = _strategy;
    emit Deployed(_reserve, _strategy);
  }

  /* ============ External Functions ============ */

  function flush(
    IStrategy strategy,
    IReserve reserve,
    address _recipient, 
    uint256 _amount
  ) external override returns (bool) {
    strategy.distribute();
    reserve.withdrawTo(_recipient,_amount);

    emit Flushed(_recipient,_amount);
  }

}