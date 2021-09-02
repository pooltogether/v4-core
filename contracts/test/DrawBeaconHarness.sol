pragma solidity 0.8.6;

import "../DrawBeacon.sol";

/* solium-disable security/no-block-members */
contract DrawBeaconHarness is DrawBeacon {

  uint256 internal time;
  function setCurrentTime(uint256 _time) external {
    time = _time;
  }

  function _currentTime() internal override view returns (uint256) {
    return time;
  }

  function setRngRequest(uint32 requestId, uint32 lockBlock) external {
    rngRequest.id = requestId;
    rngRequest.lockBlock = lockBlock;
  }

  function saveRNGRequestWithDraw(uint256 randomNumber) external {
    _saveRNGRequestWithDraw(randomNumber);
  }
}