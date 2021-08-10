// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ClaimableDrawPrizeStrategyHarness.sol";
import "../external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the ClaimableDrawPrizeStrategyHarness.
contract ClaimableDrawPrizeStrategyHarnessProxyFactory is ProxyFactory {

  ClaimableDrawPrizeStrategyHarness public instance;

  constructor () {
    instance = new ClaimableDrawPrizeStrategyHarness();
  }

  function create() external returns (ClaimableDrawPrizeStrategyHarness) {
    return ClaimableDrawPrizeStrategyHarness(deployMinimal(address(instance), ""));
  }

}