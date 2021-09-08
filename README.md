# PoolTogether Tsunami Prize Strategy Contracts

[![Coverage Status](https://coveralls.io/repos/github/pooltogether/<NAME_OF_NEW_REPO>/badge.svg?branch=master)](https://coveralls.io/github/pooltogether/pooltogether-proxy-factory?branch=master)

![Tests](https://github.com/pooltogether/pooltogether-contract-tsunami/actions/workflows/main.yml/badge.svg)


## Tasks

### Push Draw

yarn hardhat push-draw [DRAW_HISTORY_ADDRESS] [DRAW_ID] [TIMESTAMP] [WINNING_RANDOM_NUMBER]
yarn hardhat push-draw 0x4B13F387aBb597ce43f92B9Dd0e8Bc90fd44F5F8 0 1631071104 0101010101

### Set Draw Settings

The distributions params are defined in `hardhat/drawSettingsDistributions.js` since passing in arrays in the console isn't supported.

yarn hardhat push-draw [TsunamiDrawCalculator_ADDRESS] [DRAW_ID] [BIT_RANGE_SIZE] [MATCH_CARDINAlITY] [PICK_COST] [PRIZE]
yarn hardhat set-draw-settings 0xEbF30c049645795805bb96F2176767ED889b8e97 0 4 5 1 1

### Deposit To

yarn hardhat push-draw [PRIZE_POOL_ADDRESS] [TO] [AMOUNT] [CONTROLLED_TOKEN]
yarn hardhat push-draw 0x4EE4Ac12335450FDE022279Cd9bF3Be33F6b1A59 0x0000000000000000000000000000000000000000 0 0xf298711CbA45926fE7758197a8ef7A877b4A2dDA