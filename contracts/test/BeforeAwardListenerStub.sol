pragma solidity 0.8.6;

import "../prize-strategy/BeforeAwardListener.sol";

/* solium-disable security/no-block-members */
contract BeforeAwardListenerStub is BeforeAwardListener {

  event Awarded();

  function beforePrizePoolAwarded(uint256 randomNumber, uint256 prizePeriodStartedAt, uint256 prize) external override {
    emit Awarded();
  }
}