// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "../prize-pool/PrizePool.sol";
import "./YieldSourceStub.sol";

contract PrizePoolHarness is PrizePool {

  uint256 public currentTime;

  YieldSourceStub public stubYieldSource;

  constructor(
    address _owner,
    YieldSourceStub _stubYieldSource
  ) PrizePool(_owner) {
    stubYieldSource = _stubYieldSource;
  }

  function mint(address _to, uint256 _amount, IControlledToken _controlledToken) external {
    _mint(_to, _amount, _controlledToken);
  }

  function supply(uint256 mintAmount) external {
    _supply(mintAmount);
  }

  function redeem(uint256 redeemAmount) external {
    _redeem(redeemAmount);
  }

  function setCurrentTime(uint256 _currentTime) external {
    currentTime = _currentTime;
  }

  function _currentTime() internal override view returns (uint256) {
    return currentTime;
  }

  function _canAwardExternal(address _externalToken) internal override view returns (bool) {
    return stubYieldSource.canAwardExternal(_externalToken);
  }

  function _token() internal override view returns (IERC20) {
    return IERC20(stubYieldSource.depositToken());
  }

  function _balance() internal override returns (uint256) {
    return stubYieldSource.balanceOfToken(address(this));
  }

  function _supply(uint256 mintAmount) internal override {
    return stubYieldSource.supplyTokenTo(mintAmount, address(this));
  }

  function _redeem(uint256 redeemAmount) internal override returns (uint256) {
    return stubYieldSource.redeemToken(redeemAmount);
  }
}
