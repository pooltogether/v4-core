// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./prize-strategy/DrawStrategistManager.sol";
import "./external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the DrawStrategistManager.
contract DrawStrategistManagerProxyFactory is ProxyFactory {

  DrawStrategistManager public instance;

  constructor () {
    instance = new DrawStrategistManager();
  }

  function create() external returns (DrawStrategistManager) {
    return DrawStrategistManager(deployMinimal(address(instance), ""));
  }

}