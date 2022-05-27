// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title  PoolTogether TokenVault
 * @author PoolTogether Inc Team
 * @notice The TokenVault contract stores ERC20 tokens that are swapped through the PrizePoolLiquidator contract.
 *         Stakers are then able to claim their share of rewards by interacting with the GaugeReward contract.
 *         Rewards are then transferred directly from the TokenVault to the staker account.
 */
contract TokenVault is Manageable {
    using SafeERC20 for IERC20;

    /// @notice Tracks addresses approved to spend tokens from the vault.
    mapping(address => bool) public approved;

    /**
     * @notice Emitted when a `spender` address is approved to spend tokens from the vault.
     * @param spender Address that is approved to spend tokens from the vault
     * @param approved Whether the spender is approved to spend tokens from the vault or not
     */
    event Approved(address indexed spender, bool approved);

    /**
     * @notice Constructs TokenVault
     * @param _owner Owner address
     */
    constructor(address _owner) Ownable(_owner) {
        require(_owner != address(0), "TVault/owner-not-zero-address");
    }

    /**
     * @notice Approves the given `spender` address to spend ERC20 tokens from the vault.
     * @dev Only callable by the owner.
     * @param _spender Address that will spend the tokens
     * @param _approve Whether to approve `spender` or not
     */
    function setApproval(address _spender, bool _approve) external onlyOwner {
        approved[_spender] = _approve;
        emit Approved(_spender, _approve);
    }

    /**
     * @notice Decrease allowance of ERC20 tokens held by this contract.
     * @dev Only callable by the owner or asset manager.
     * @dev Current allowance should be computed off-chain to avoid any underflow.
     * @param _token Address of the ERC20 token to decrease allowance for
     * @param _spender Address of the spender of the tokens
     * @param _amount Amount of tokens to decrease allowance by
     */
    function decreaseERC20Allowance(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) external onlyManagerOrOwner {
        _token.safeDecreaseAllowance(_spender, _amount);
    }

    /**
     * @notice Increase allowance of ERC20 tokens held by this contract.
     * @dev Only callable by the owner or asset manager.
     * @dev Allowance can only be increased for approved `spender` addresses.
     * @dev Current allowance should be computed off-chain to avoid any overflow.
     * @param _token Address of the ERC20 token to increase allowance for
     * @param _spender Address of the spender of the tokens
     * @param _amount Amount of tokens to increase allowance by
     */
    function increaseERC20Allowance(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) external onlyManagerOrOwner {
        require(approved[_spender], "TVault/spender-not-approved");
        _token.safeIncreaseAllowance(_spender, _amount);
    }
}
