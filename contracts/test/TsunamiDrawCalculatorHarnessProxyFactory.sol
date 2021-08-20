// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./TsunamiDrawCalculatorHarness.sol";
import "../external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the TsunamiDrawCalculatorHarness.
contract TsunamiDrawCalculatorHarnessProxyFactory is ProxyFactory {

  TsunamiDrawCalculatorHarness public instance;

  constructor () {
    instance = new TsunamiDrawCalculatorHarness();
  }

  function create() external returns (TsunamiDrawCalculatorHarness) {
    return TsunamiDrawCalculatorHarness(deployMinimal(address(instance), ""));
  }

}