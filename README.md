# PoolTogether V4 Strategy Contracts

[![Coverage Status](https://coveralls.io/repos/github/pooltogether/<NAME_OF_NEW_REPO>/badge.svg?branch=master)](https://coveralls.io/github/pooltogether/pooltogether-proxy-factory?branch=master)

![Tests](https://github.com/pooltogether/pooltogether-contract-tsunami/actions/workflows/main.yml/badge.svg)

*Smart Contracts*

- [DrawBeacon](pooltogether/pooltogether-contract-tsunami)
- DrawCalculator
- DrawHistory
- DrawPrizes
- PrizeFlush
- PrizeSplitStrategy
- Reserve


# Getting Started

The project is made available as a NPM package.

```sh
$ yarn add @pooltogether/pooltogether-contracts
```

The repo can be cloned from Github for contributions.

```sh
$ git clone https://github.com/pooltogether/pooltogether-contract-tsunami
```

```sh
$ yarn
```

```sh$ 
npm install
```

We use [direnv](https://direnv.net/) to manage environment variables.  You'll likely need to install it.

```sh
cp .envrc.example .envrv
```

To run fork scripts, deploy or perform any operation with a mainnet/testnet node you will need an Infura API key.

# Testing

We use [Hardhat](https://hardhat.dev) and [hardhat-deploy](https://github.com/wighawag/hardhat-deploy)

To run unit & integration tests:

```sh
$ yarn test
```

To run coverage:

```sh
$ yarn coverage
```

# Fork Testing

Ensure your environment variables are set up.  Make sure your Alchemy URL is set.  Now start a local fork:

```sh
$ yarn start-fork
```

Setup account impersonation and transfer eth:

```sh
$ ./scripts/setup.sh
```

# Deployment

## Deploy Locally

Start a local node and deploy the top-level contracts:

```bash
$ yarn start
```

NOTE: When you run this command it will reset the local blockchain.


## Overview

The V4 PoolTogether smart contracts facilitate a "pull" based system to claim interst prize payouts
