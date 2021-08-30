pragma solidity 0.8.6;

import "../DrawBeaconBase.sol";

/* solium-disable security/no-block-members */
contract DrawBeaconBaseHarness is DrawBeaconBase {

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

  function _saveRNGRequestWithDraw(uint256 randomNumber) internal override virtual returns (uint256){
    return 0;
  }
}