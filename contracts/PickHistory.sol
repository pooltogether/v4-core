// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";

contract PickHistory is OwnableUpgradeable {
  using SafeMathUpgradeable for uint256;
  using SafeCastUpgradeable for uint256;

  function initialize () public initializer {

  }

  /* ============ External Functions ============ */

  function updateBalance(address user, uint256 balance, uint256 currentDrawNumber) external {

  }

  function setRandomNumber(bytes32 randomNumber, uint256 currentDrawNumber) external {

  }

  function getBalance(address user, uint256 drawNumber) external returns (uint256) {

  }

  function getRandonNumber(address user, uint256 drawNumber) external view returns (bytes32) {

  }

  /* ============ Internal Functions ============ */


}