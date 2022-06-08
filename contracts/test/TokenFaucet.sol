// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
  * @title TokenFaucet
  * @notice Allow users to claim tokens that were deposited in this contract.
  */
contract TokenFaucet {
  using SafeERC20 for IERC20;

  /**
    * @notice Drips some tokens to caller.
    * @dev We send 0.01% of our tokens to the caller. Over time, the amount will tend toward and eventually reach zero.
    * @param _token Address of the token to drip
    */
  function drip(IERC20 _token) public {
      uint256 _balance = _token.balanceOf(address(this));
      require(_balance > 0, "TokenFaucet/empty-token-balance");
      _token.safeTransfer(msg.sender, _balance / 10000); // 0.01%
  }
}
