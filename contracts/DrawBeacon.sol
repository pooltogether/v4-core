// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/TicketInterface.sol";
import "./ClaimableDraw.sol";
import "./DrawHistory.sol";
import "./DrawBeaconBase.sol";

contract DrawBeacon is Initializable, 
                       OwnableUpgradeable, 
                       DrawHistory,
                       DrawBeaconBase {

  /**
    * @notice Initialize the DrawBeacon smart contract.
    * @param _drawManager Draw manager address
    * @param _prizePeriodStart The starting timestamp of the prize period.
    * @param _prizePeriodSeconds The duration of the prize period in seconds
    * @param _rng The RNG service to use
  */
  function initializeDrawBeacon (
    address _drawManager,
    uint256 _prizePeriodStart,
    uint256 _prizePeriodSeconds,
    RNGInterface _rng
  ) external initializer returns (bool) {
    __Ownable_init();

    DrawHistory.initialize(
      _drawManager
    );

    DrawBeaconBase.initialize(
      _prizePeriodStart,
      _prizePeriodSeconds,
      _rng
    );

    return true;
  }

  /**
    * @notice Create a new draw connected to a RNG request.
    * @dev    Create a new draw using the randomly generated number and curent block timestamp.
    *
    * @param randomNumber Randomly generated number
  */
  function _saveRNGRequestWithDraw(uint256 randomNumber) internal override returns (uint256) {
    return _createDraw(uint32(block.timestamp), randomNumber);
  }

}