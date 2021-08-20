// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ClaimableDrawPrizeStrategy.sol";
import "./external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the ClaimableDrawPrizeStrategy.
contract ClaimableDrawPrizeStrategyProxyFactory is ProxyFactory {

  ClaimableDrawPrizeStrategy public instance;

  constructor () {
    instance = new ClaimableDrawPrizeStrategy();
  }

  function create() external returns (ClaimableDrawPrizeStrategy) {
    return ClaimableDrawPrizeStrategy(deployMinimal(address(instance), ""));
  }

}