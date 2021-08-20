// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./ClaimableDrawHarness.sol";
import "../external/openzeppelin/ProxyFactory.sol";

/// @title Creates a minimal proxy to the ClaimableDrawHarness.
contract ClaimableDrawHarnessProxyFactory is ProxyFactory {

  ClaimableDrawHarness public instance;

  constructor () {
    instance = new ClaimableDrawHarness();
  }

  function create() external returns (ClaimableDrawHarness) {
    return ClaimableDrawHarness(deployMinimal(address(instance), ""));
  }

}