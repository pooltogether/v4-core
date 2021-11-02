// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IPrizePool.sol";
import "../interfaces/ITicket.sol";

/**
 * @notice Secp256k1 signature values.
 * @param v `v` portion of the signature
 * @param r `r` portion of the signature
 * @param s `s` portion of the signature
 */
struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @title Allows users to approve and deposit EIP-2612 compatible tokens into a prize pool in a single transaction.
contract EIP2612PermitAndDeposit {
    using SafeERC20 for IERC20;

    /**
     * @notice Permits this contract to spend on a user's behalf, and deposits into the prize pool.
     * @custom:experimental This function has not been audited yet.
     * @dev The `spender` address required by the permit function is the address of this contract.
     * @param _owner Token owner's address (Authorizer)
     * @param _amount Amount of tokens to deposit
     * @param _deadline Timestamp at which the signature expires
     * @param _permitSignature Permit signature
     * @param _delegateSignature Delegate signature
     * @param _prizePool Address of the prize pool to deposit into
     * @param _to Address that will receive the tickets
     * @param _delegate The address to delegate the prize pool tickets to
     */
    function permitAndDepositToAndDelegate(
        address _owner,
        uint256 _amount,
        uint256 _deadline,
        Signature calldata _permitSignature,
        Signature calldata _delegateSignature,
        IPrizePool _prizePool,
        address _to,
        address _delegate
    ) external {
        require(msg.sender == _owner, "EIP2612PermitAndDeposit/only-signer");

        ITicket _ticket = _prizePool.getTicket();
        address _token = _prizePool.getToken();

        IERC20Permit(_token).permit(
            _owner,
            address(this),
            _amount,
            _deadline,
            _permitSignature.v,
            _permitSignature.r,
            _permitSignature.s
        );

        _depositTo(_token, _owner, _amount, address(_prizePool), _to);

        _ticket.delegateWithSignature(
            _owner,
            _delegate,
            _deadline,
            _delegateSignature.v,
            _delegateSignature.r,
            _delegateSignature.s
        );
    }

    /**
     * @notice Deposits user's token into the prize pool.
     * @param _token Address of the EIP-2612 token to approve and deposit
     * @param _owner Token owner's address (Authorizer)
     * @param _amount Amount of tokens to deposit
     * @param _prizePool Address of the prize pool to deposit into
     * @param _to Address that will receive the tickets
     */
    function _depositTo(
        address _token,
        address _owner,
        uint256 _amount,
        address _prizePool,
        address _to
    ) internal {
        IERC20(_token).safeTransferFrom(_owner, address(this), _amount);
        IERC20(_token).safeIncreaseAllowance(_prizePool, _amount);
        IPrizePool(_prizePool).depositTo(_to, _amount);
    }
}
