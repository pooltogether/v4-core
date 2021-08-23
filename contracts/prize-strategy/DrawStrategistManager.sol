// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./BeforeAwardListener.sol";
import "../ClaimableDraw.sol";
import "./PeriodicPrizeStrategy.sol";

/* solium-disable security/no-block-members */
/// @title Manages Sablier streams for Prize Pools.  Can be attached to Periodic Prize Strategies so that streams are withdrawn before awarding.
contract DrawStrategistManager is Initializable, BeforeAwardListener {

  /// @notice The address of the PrizePool contract
  OwnableUpgradeable public prizePool;

  /// @notice The address of the ClaimambleDraw contract
  ClaimableDraw public claimableDraw;

  mapping(address => uint256) internal sablierStreamIds;

  /// @param _prizePool The address of the PrizePool contract
  /// @param _claimableDraw The address of the ClaimambleDraw contract
  function initialize(OwnableUpgradeable _prizePool, ClaimableDraw _claimableDraw) external initializer onlyPrizePoolOwner(prizePool) {
    require(address(_claimableDraw) != address(0), "DrawStrategistManager/prizepool-not-zero-address");
    prizePool = _prizePool;
    claimableDraw = _claimableDraw;
  }

  /// @notice Allows a periodic prize strategy to call the manager to create a new draw.
  function beforePrizePoolAwarded(uint256 randomNumber, uint256, uint256 prize) external override onlyPrizePoolOwner(prizePool) {
    claimableDraw.createDraw(randomNumber, uint32(block.timestamp), prize);
  }

  modifier onlyPrizePoolOwner(OwnableUpgradeable prizePool) {
    require(msg.sender == prizePool.owner(), "DrawStrategistManager/caller-not-owner");
    _;
  }

}