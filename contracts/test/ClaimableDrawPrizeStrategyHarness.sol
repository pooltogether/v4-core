pragma solidity 0.8.6;

import "../ClaimableDrawPrizeStrategy.sol";
import "../test/PeriodicPrizeStrategyDistributorInterface.sol";

/* solium-disable security/no-block-members */
contract ClaimableDrawPrizeStrategyHarness is ClaimableDrawPrizeStrategy {

  PeriodicPrizeStrategyDistributorInterface distributor;

  function createDraw(uint256 randomNumber, uint32 timestamp, uint256 prize) external returns (uint256){
    return claimableDraw.createDraw(randomNumber, timestamp, prize);
  } 

  function setDistributor(PeriodicPrizeStrategyDistributorInterface _distributor) external {
    distributor = _distributor;
  }

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

  // NOTE: Disabled to test _distribute with createDraw 
  // function _distribute(uint256 randomNumber) internal override {
  //   distributor.distribute(randomNumber);
  // }

  function forceBeforeAwardListener(BeforeAwardListenerInterface listener) external {
    beforeAwardListener = listener;
  }

  function awardPrizeSplitAmount(address target, uint256 amount, uint8 tokenIndex) internal {
    _awardToken(target, amount, tokenIndex);
  }

  function distributePrizeSplit(uint256 randomNumber) external {
    _distribute(randomNumber);
  }
}