// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPrizePool.sol";

/// @title Allows users to approve and deposit EIP-2612 compatible tokens into a prize pool in a single transaction.
contract EIP2612PermitAndDeposit {
    using SafeERC20 for IERC20;

    /**
     * @notice Permits this contract to spend on a user's behalf, and deposits into the prize pool.
     * @dev The `spender` address required by the permit function is the address of this contract.
     * @param token Address of the EIP-2612 token to approve and deposit.
     * @param owner Token owner's address (Authorizer).
     * @param amount Amount of tokens to deposit.
     * @param deadline Timestamp at which the signature expires.
     * @param v `v` portion of the signature.
     * @param r `r` portion of the signature.
     * @param s `s` portion of the signature.
     * @param prizePool Address of the prize pool to deposit into.
     * @param to Address that will receive the tickets.
     */
    function permitAndDepositTo(
        address token,
        address owner,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address prizePool,
        address to
    ) external {
        require(msg.sender == owner, "EIP2612PermitAndDeposit/only-signer");

        IERC20Permit(token).permit(owner, address(this), amount, deadline, v, r, s);

        _depositTo(token, owner, amount, prizePool, to);
    }

    /**
     * @notice Deposits user's token into the prize pool.
     * @param token Address of the EIP-2612 token to approve and deposit.
     * @param owner Token owner's address (Authorizer).
     * @param amount Amount of tokens to deposit.
     * @param prizePool Address of the prize pool to deposit into.
     * @param to Address that will receive the tickets.
     */
    function _depositTo(
        address token,
        address owner,
        uint256 amount,
        address prizePool,
        address to
    ) internal {
        IERC20(token).safeTransferFrom(owner, address(this), amount);
        IERC20(token).safeApprove(prizePool, amount);
        IPrizePool(prizePool).depositTo(to, amount);
    }
}
