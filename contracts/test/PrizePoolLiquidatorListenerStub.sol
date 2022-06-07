// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../interfaces/IPrizePoolLiquidatorListener.sol";

contract PrizePoolLiquidatorListenerStub is IPrizePoolLiquidatorListener {

    event AfterSwap(
        IPrizePool prizePool,
        ITicket ticket,
        uint256 ticketAmount,
        IERC20 token,
        uint256 tokenAmount
    );

    function afterSwap(IPrizePool prizePool, ITicket ticket, uint256 ticketAmount, IERC20 token, uint256 tokenAmount) external override {
        emit AfterSwap(
            prizePool,ticket,ticketAmount,token,tokenAmount
        );
    }
}
