// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IPrizePool.sol";
import "./ITicket.sol";

/**
 * @author PoolTogether Inc Team
 */
interface IPrizePoolLiquidatorListener {
    function afterSwap(IPrizePool prizePool, ITicket ticket, uint256 ticketAmount, IERC20 token, uint256 tokenAmount) external;
}
