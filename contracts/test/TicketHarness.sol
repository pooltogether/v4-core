// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "../Ticket.sol";

contract TicketHarness is Ticket {
  using SafeCastUpgradeable for uint256;

  function flashLoan(address _to, uint256 _amount) external {
    _mint(_to, _amount);
    _burn(_to, _amount);
  }

  function burn(address _from, uint256 _amount) external {
    _burn(_from, _amount);
  }

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function mintTwice(address _to, uint256 _amount) external {
    _mint(_to, _amount);
    _mint(_to, _amount);
  }

  /// @dev we need to use a different function name than `transfer`
  /// otherwise it collides with the `transfer` function of the `ERC20Upgradeable` contract
  function transferTo(address _sender, address _recipient, uint256 _amount) external {
    _transfer(_sender, _recipient, _amount);
  }

  function getBalanceTx(address _user, uint32 _target) external returns (uint256) {
    Account storage account = userTwabs[_user];
    return _getBalanceAt(account.twabs, account.details, _target);
  }

  function getAverageBalanceTx(address _user, uint32 _startTime, uint32 _endTime) external returns (uint256) {
    Account storage account = userTwabs[_user];
    return _getAverageBalanceBetween(account.twabs, account.details, uint32(_startTime), uint32(_endTime));
  }
}
