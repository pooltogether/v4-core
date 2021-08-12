// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "../Ticket.sol";

contract TicketHarness is Ticket {
  using SafeCastUpgradeable for uint256;

  function burn(address _from, uint256 _amount) external {
    _burn(_from, _amount);
  }

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  /// @dev we need to use a different function name than `transfer`
  /// otherwise it collides with the `transfer` function of the `ERC20Upgradeable` contract
  function transferTo(address _sender, address _recipient, uint256 _amount) external {
    _transfer(_sender, _recipient, _amount);
  }

  function mostRecentTwabIndexOfUser(address _user) external view returns (uint256) {
    return _mostRecentTwabIndexOfUser(_user);
  }

  function mostRecentTwabIndexOfTotalSupply() external view returns (uint256) {
    return _mostRecentTwabIndexOfTotalSupply();
  }

  function getBalanceTx(address _user, uint32 _target) external returns (uint256) {
    return _getBalance(_user, _target);
  }

  function getAverageBalanceTx(address _user, uint32 _startTime, uint32 _endTime) external returns (uint256) {
    return _getAverageBalance(_user, _startTime, _endTime);
  }

  function newUserTwab(address _user, uint16 _nextTwabIndex) external returns (uint16) {
    return _newUserTwab(_user, _nextTwabIndex);
  }

  function newTotalSupplyTwab(uint16 _nextTwabIndex) external returns (uint16) {
    return _newTotalSupplyTwab(_nextTwabIndex);
  }
}
