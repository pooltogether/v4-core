// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ClaimableDraw.sol";
import "./external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the ClaimableDraw.
contract ClaimableDrawProxyFactory is ProxyFactory {

  ClaimableDraw public instance;

  constructor () {
    instance = new ClaimableDraw();
  }

  function create() external returns (ClaimableDraw) {
    return ClaimableDraw(deployMinimal(address(instance), ""));
  }

}