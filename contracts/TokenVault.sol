// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
    * @title  PoolTogether Vault
    * @author PoolTogether Inc Team
 */
contract Vault is Manageable {
    using SafeERC20 for IERC20;

    mapping(address => bool) public approved;

    /**
     * @notice Constructs Vault
     * @param _owner Owner address
     */
    constructor(address _owner) Ownable(_owner) {}

    function setApproved(address _account, bool _approved) external onlyOwner {
        approved[_account] = _approved;
    }

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
    ) external onlyManagerOrOwner {
        token.safeDecreaseAllowance(spender, amount);
    }

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
    ) external onlyManagerOrOwner {
        require(approved[spender], "Spender must be approved");
        token.safeIncreaseAllowance(spender, amount);
    }
}
