// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title  PoolTogether V4 IVault
 * @author PoolTogether Inc Team
 * @notice The GaugeReward interface.
 */
interface IVault {
    /**
     * @notice Decrease allowance of ERC20 tokens held by this contract.
     * @dev Only callable by the owner or asset manager.
     * @dev Current allowance should be computed off-chain to avoid any underflow.
     * @param token Address of the ERC20 token to decrease allowance for
     * @param spender Address of the spender of the tokens
     * @param amount Amount of tokens to decrease allowance by
     */
    function decreaseERC20Allowance(
        IERC20 token,
        address spender,
        uint256 amount
    ) external;

    /**
     * @notice Increase allowance of ERC20 tokens held by this contract.
     * @dev Only callable by the owner or asset manager.
     * @dev Current allowance should be computed off-chain to avoid any overflow.
     * @param token Address of the ERC20 token to increase allowance for
     * @param spender Address of the spender of the tokens
     * @param amount Amount of tokens to increase allowance by
     */
    function increaseERC20Allowance(
        IERC20 token,
        address spender,
        uint256 amount
    ) external;
}
