<p align="center">
  <a href="https://github.com/pooltogether/pooltogether--brand-assets">
    <img src="/banner.png" alt="PoolTogether Brand" style="max-width:100%;" width="1000">
  </a>
</p>

# PoolTogether V4 Strategy Contracts


[![<PoolTogether>](https://circleci.com/gh/pooltogether/pooltogether-pool-contracts.svg?style=shield)](https://circleci.com/gh/pooltogether/pooltogether-contract-tsunami)
[![Coverage Status](https://coveralls.io/repos/github/pooltogether/pooltogether-contract-tsunami/badge.svg?branch=master)](https://coveralls.io/github/pooltogether/pooltogether-contract-tsunami?branch=master)
[![built-with openzeppelin](https://img.shields.io/badge/built%20with-OpenZeppelin-3677FF)](https://docs.openzeppelin.com/)

<strong>Have questions or want the latest news?</strong>
<br/>Join the PoolTogether Discord or follow us on Twitter:

[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://discord.gg/JFBPMxv5tr)
[![Twitter](https://badgen.net/badge/icon/twitter?icon=twitter&label)](https://twitter.com)

**Documention**<br>
https://docs.pooltogether.com/

**Deplyoments**<br>
- [Ethereum](https://docs.pooltogether.com/resources/networks/ethereum)
- [Matic](https://docs.pooltogether.com/resources/networks/matic)

# Overview
- [DrawBeacon](/contracts/DrawBeacon.sol)
- [DrawCalculator](/contracts/DrawCalculator.sol)
- [DrawHistory](/contracts/DrawHistory.sol)
- [DrawPrizes](/contracts/DrawPrizes.sol)
- [PrizeFlush](/contracts/PrizeFlush.sol)
- [PrizeSplitStrategy](/contracts/PrizeSplitStrategy.sol)
- [Reserve](/contracts/Reserve.sol)

Periphery and supporting contracts:

- https://github.com/pooltogether/v4-periphery
- https://github.com/pooltogether/v4-oracle-timelocks


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
