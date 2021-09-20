// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

library OracleTimelockLib{

    struct Timelock {
      uint32 drawId;
      uint128 timestamp;
    }

}