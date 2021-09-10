// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

// TODO: replace by non upgradeable contracts once PR to migrate to constructor is merged
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";

import "./interfaces/IPrizeReserve.sol";
import "./libraries/TwabLibrary.sol";

/// @notice Contract that holds the prize tokens (ie: interest) captured at each draw.
/// @dev The total amount captured during a prize period (ie: 7 days) is signaled to the Draw Settings Manager.
/// @dev The Draw Settings Manager then decide how many picks get each pools.
/// @dev Only the `owner` is allowed to `withdraw` tokens from the prize reserve.
contract PrizeReserve is IPrizeReserve, OwnerOrManager {
  using SafeCast for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /// @notice Prize pool `sponsorshipToken` captured by the reserve.
  IControlledToken private _sponsorshipToken;

  /// @notice The minimum length of time a twab should exist.
  /// @dev Once the twab ttl expires, its storage slot is recycled.
  uint32 public constant TWAB_TIME_TO_LIVE = 24 weeks;

  /// @notice The maximum number of twab entries
  uint16 public constant MAX_CARDINALITY = 65535;

  /// @notice A struct containing Reserve details
  /// @param amount Accumulated amount of `sponsorshipToken`
  /// @param nextTwabIndex Next available index to store a new twab
  /// @param cardinality Number of recorded twabs (plus one)
  struct ReserveDetails {
    uint224 amount;
    uint16 nextTwabIndex;
    uint16 cardinality;
  }

  /// @notice Combines Reserve details with their twab history
  /// @param details Reserve details
  /// @param twabs Twabs history
  struct Reserve {
    ReserveDetails details;
    TwabLibrary.Twab[MAX_CARDINALITY] twabs;
  }

  /// @notice Accumulated `amount` of `sponsorshipToken` held by this contract. Ordered by `timestamp`, earliest to latest.
  Reserve internal _balanceTwab;

  /// @notice Accumulated `amount` of `sponsorshipToken` withdrawn from this contract. Ordered by `timestamp`, earliest to latest.
  Reserve internal _withdrawalTwab;

  constructor(IPrizePool _prizePool) {
    __Ownable_init();

    IControlledToken[] memory _tokens = _prizePool.tokens();

    _sponsorshipToken = _tokens[1];

    emit Created(_sponsorshipToken);
  }

  /* ============ External Functions ============ */

  /// @notice Record `prizePool` contribution to the prize reserve.
  /// @dev We only increase twab balance if sponsorship token balance has changed.
  /// @return True if checkpoint was successful.
  function checkpoint() external override returns (bool) {
    uint256 _currentSponsorshipTokenBalance = _sponsorshipToken.balanceOf(address(this));

    if (_getBalanceAt(block.timestamp) != _currentSponsorshipTokenBalance) {
      _increaseBalanceTwab(_currentSponsorshipTokenBalance + _withdrawalTwab.details.amount - _balanceTwab.details.amount);
    }

    return true;
  }

  /// @notice Retrieve current reserve balance.
  /// @return Current reserve balance.
  function getBalance() external override view returns (uint256) {
    return _sponsorshipToken.balanceOf(address(this));
  }

  /// @notice Retrieve reserve balance at `target`.
  /// @param _target Timestamp at which the reserve balance is to be retrieved.
  /// @return Reserve balance at `target`.
  function getBalanceAt(uint256 _target) external override view returns (uint256) {
    return _getBalanceAt(_target);
  }

  /// @notice Withdraw `amount` of `sponsorshipToken` held by this contract.
  /// @param _to Recipient address that will receive `amount` of `sponsorshipToken`.
  /// @param _amount Amount of `sponsorshipToken` to withdraw.
  /// @return True if withdrawal was successful.
  function withdraw(address _to, uint256 _amount) external override onlyOwner returns (bool) {
    IERC20Upgradeable(_sponsorshipToken).safeTransfer(_to, _amount);

    _increaseWithdrawalTwab(_amount);

    emit Withdrawn(msg.sender, _to, _amount);

    return true;
  }

  /* ============ Internal Functions ============ */

  /// @notice Retrieve reserve balance at `target`.
  /// @param _target Timestamp at which the reserve balance is to be retrieved.
  /// @return Reserve balance at `target`.
  function _getBalanceAt(uint256 _target) internal view returns (uint256) {
    uint32 _currentTimestamp = uint32(block.timestamp);
    uint32 _targetTimestamp = uint32(_target);

    ReserveDetails memory _balanceTwabDetails = _balanceTwab.details;
    ReserveDetails memory _withdrawalTwabDetails = _withdrawalTwab.details;

    uint256 _targetBalanceAmount = TwabLibrary.getBalanceAt(
      _balanceTwabDetails.cardinality,
      _balanceTwabDetails.nextTwabIndex,
      _balanceTwab.twabs,
      _balanceTwabDetails.amount,
      _targetTimestamp,
      _currentTimestamp
    );

    uint256 _targetWithdrawalAmount = TwabLibrary.getBalanceAt(
      _withdrawalTwabDetails.cardinality,
      _withdrawalTwabDetails.nextTwabIndex,
      _withdrawalTwab.twabs,
      _withdrawalTwabDetails.amount,
      _targetTimestamp,
      _currentTimestamp
    );

    return _targetBalanceAmount - _targetWithdrawalAmount;
  }

  /// @notice Increases amount and records a new twab.
  /// @param _reserve Reserve whose amount will be increased.
  /// @param _amount Amount to increase the reserve by.
  /// @return twab Reserve's latest TWAB.
  /// @return isNew Whether the TWAB is new.
  function _increaseTwab(
    Reserve storage _reserve,
    uint256 _amount
  ) internal returns (TwabLibrary.Twab memory twab, bool isNew) {
    ReserveDetails memory details = _reserve.details;

    uint16 nextTwabIndex;
    uint16 cardinality;

    (nextTwabIndex, cardinality, twab, isNew) = TwabLibrary.update(
      details.amount,
      details.nextTwabIndex,
      details.cardinality,
      _reserve.twabs,
      uint32(block.timestamp),
      TWAB_TIME_TO_LIVE
    );

    _reserve.details = ReserveDetails({
      amount: (details.amount + _amount).toUint224(),
      nextTwabIndex: nextTwabIndex,
      cardinality: cardinality
    });
  }

  /// @notice Increases balance amount and records a new twab.
  /// @param _amount Amount to increase the balance by.
  function _increaseBalanceTwab(uint256 _amount) internal {
    (TwabLibrary.Twab memory twab, bool isNew) = _increaseTwab(_balanceTwab, _amount);

    if (isNew) {
      emit NewBalanceTwab(twab);
    }
  }

  /// @notice Increases withdrawal amount and records a new twab.
  /// @param _amount Amount to increase the withdrawal by.
  function _increaseWithdrawalTwab(uint256 _amount) internal {
    (TwabLibrary.Twab memory twab, bool isNew) = _increaseTwab(_withdrawalTwab, _amount);

    if (isNew) {
      emit NewWithdrawalTwab(twab);
    }
  }
}
