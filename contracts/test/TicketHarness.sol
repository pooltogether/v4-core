// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../Ticket.sol";

contract TicketHarness is Ticket {
  function moduloCardinality(uint256 _index) external pure returns (uint256) {
    return _moduloCardinality(_index);
  }

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

  function binarySearch(
    address _user,
    uint32 _target
  ) external view returns (Twab memory beforeOrAt, Twab memory atOrAfter) {
    (beforeOrAt, atOrAfter) = _binarySearch(_user, _target);
  }

  function binarySearchTotalSupply(
    uint32 _target
  ) external view returns (TotalSupplyTwab memory beforeOrAt, TotalSupplyTwab memory atOrAfter) {
    (beforeOrAt, atOrAfter) = _binarySearchTotalSupply(_target);
  }

  function newTwab(address _user, uint16 _nextTwabIndex) external {
    _newTwab(_user, _nextTwabIndex);
  }

  function newTotalSupplyTwab(uint16 _nextTwabIndex) external {
    _newTotalSupplyTwab(_nextTwabIndex);
  }
}
