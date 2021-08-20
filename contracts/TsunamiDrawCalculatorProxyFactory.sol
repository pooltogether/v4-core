// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./TsunamiDrawCalculator.sol";
import "./external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the TsunamiDrawCalculator.
contract TsunamiDrawCalculatorProxyFactory is ProxyFactory {

  TsunamiDrawCalculator public instance;

  constructor () {
    instance = new TsunamiDrawCalculator();
  }

  function create() external returns (TsunamiDrawCalculator) {
    return TsunamiDrawCalculator(deployMinimal(address(instance), ""));
  }

}