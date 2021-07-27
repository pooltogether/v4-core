// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../Ticket.sol";

contract TicketHarness is Ticket {
  function getTwabIndex(uint256 _index) external pure returns (uint256) {
    return _getTwabIndex(_index);
  }

  function burn(address _from, uint256 _amount) external {
    _burn(_from, _amount);
  }

  function mint(address _to, uint256 _amount) external {
    _mint(_to, _amount);
  }

  function mostRecentTwabIndexOfUser(address _user) external view returns (uint256) {
    return _mostRecentTwabIndexOfUser(_user);
  }

  function binarySearch(
    address _user,
    uint32 _target
  ) external view returns (Twab memory beforeOrAt, Twab memory atOrAfter) {
    (beforeOrAt, atOrAfter) = _binarySearch(_user, _target);
  }

  function newTwab(address _user) external {
    _newTwab(_user);
  }

  function beforeTokenTransfer(address _from, address _to, uint256) external {
    _beforeTokenTransfer(_from, _to, 0);
  }
}
