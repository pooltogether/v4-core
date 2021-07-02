// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./interfaces/IWaveModel.sol";
import "./interfaces/IPickHistory.sol";

contract TsunamiPrizeStrategy is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeCastUpgradeable for uint256;

   /* ============ Variables ============ */
    // The pick history address.
    IPickHistory public pickHistory;

    // The active wave model address.
    IWaveModel public activeModel;

    // The pending wave model address.
    IWaveModel public pendingModel;
    
    // The pending wave model address.
    IERC20Upgradeable public token;


   /* ============ Structs ============ */

   struct Draw {
     uint256 prize;
     uint256 totalDeposits;
     uint256 timestamp;
     uint256 winningNumber;
     uint256 randomNumber;
   }
   
   struct WaveModel {
     address model;
     string name;
   }

  // Mapping of draw timestamp to draw struct
  // +---------------+-------------+
  // | DrawTimestamp | DrawStruct  |
  // +---------------+-------------+
  // | Timestamp     | DrawModel   |
  // | Timestamp     | DrawModel   |
  // +---------------+-------------+
  // mapping(uint256 => Draw) public drawHistory;
  Draw[] public drawHistory;

  // Mapping of wave model address wave model struct
  // +--------------+-------------+
  // | ModelAddress | ModelStruct |
  // +--------------+-------------+
  // | ModelA       | WaveModel   |
  // | ModelA       | WaveModel   |
  // +--------------+-------------+
  mapping(address => WaveModel) public waveModels;

  /* ============ Events ============ */
  event Initialized(

  );

  event WaveModelProposed(
    address indexed model
  );
  
  event WaveModelActivated(
    address indexed model
  );

  event Claimed(
    address indexed user,
    uint256 prize
  );

  /* ============ Initialize ============ */

  function initialize (

  ) public initializer {

  }

  /* ============ External Functions ============ */

  /**
    * Sets a pending wave model to be activated by governance 
    * called by authorized core contracts.
    *
    * @param  model          The address of the WaveModel
    */
  function setPendingWaveModel(IWaveModel model) external {
    require(address(model) != address(0), "TsunamiPrizeStrategy/model-not-zero-address");
  }

  /**
    * Sets a pending wave model to be activated by governance 
    * called by authorized core contracts.
    *
    * @param  model          The address of the WaveModel
    */
  function setActiveWaveModel(IWaveModel model) external {
    require(model == pendingModel, "TsunamiPrizeStrategy/model-not-pending-model");
  }

  /**
     * Admin function to modify chunk sizes for an asset pair.
     *
     * @param user                   Address of the user
     * @param draws                  List of the draws
     * @param pickIndices            An array of pickIndices arrays
     */
  function claim(address user, uint256[] calldata draws, uint256[][] calldata pickIndices) external {
    IERC20Upgradeable _token = token;
    IWaveModel _activeModel = activeModel;
    IPickHistory _pickHistory = pickHistory;

    // Find the last draw 
    uint256 drawHistoryLength = drawHistory.length;
    Draw memory lastDraw = drawHistory[drawHistoryLength.sub(1)];

    // User Information
    uint256 userBalance = _token.balanceOf(user);
    // uint256 userDraw = _pickHistory.getDraw(winningNumber, lastDraw.prize, lastDraw.totalDeposits, userBalance, randomNumber);

    // Draw

    // Model Execution
    // uint256 prize = _activeModel.calculate(lastDraw.winningNumber, lastDraw.prize, lastDraw.totalDeposits, userBalance, lastDraw.randomNumber);

    // emit Claimed(user, prize);

  }

  /* ============ Internal Functions ============ */

  function _distribute() internal {

  }
}