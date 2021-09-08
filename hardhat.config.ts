import '@nomiclabs/hardhat-etherscan';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-abi-exporter';
import 'hardhat-deploy';
import 'hardhat-deploy-ethers';
import 'hardhat-gas-reporter';
import 'hardhat-log-remover';
import 'solidity-coverage';
import 'hardhat-dependency-compiler';
import './hardhat/tsunami-tasks.js';
import { HardhatUserConfig } from 'hardhat/config';
import networks from './hardhat.network';

const optimizerEnabled = !process.env.OPTIMIZER_DISABLED;

const config: HardhatUserConfig = {
  abiExporter: {
    path: './abis',
    clear: true,
    flat: true,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  gasReporter: {
    currency: 'USD',
    gasPrice: 100,
    enabled: process.env.REPORT_GAS ? true : false,
  },
  mocha: {
    timeout: 30000,
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    reserveRegistry: {
      1: '0x3e8b9901dBFE766d3FE44B36c180A1bca2B9A295', // mainnet
      4: '0xaDae16a9A1B648Cdc753558Dc19780Ea824a3904', // rinkeby
      42: '0xdcC0D09beE9726E23256ebC059B7487Cd78F65a0', // kovan
      100: '0x20F29CCaE4c9886964033042c6b79c2C4C816308', // xdai
      77: '0x4d1639e4b237BCab6F908A1CEb0995716D5ebE36', // poaSokol
      137: '0x20F29CCaE4c9886964033042c6b79c2C4C816308', //matic
      80001: '0xdcC0D09beE9726E23256ebC059B7487Cd78F65a0', // mumbai
      56: '0x3e8b9901dBFE766d3FE44B36c180A1bca2B9A295', // bsc
      97: '0x3e8b9901dBFE766d3FE44B36c180A1bca2B9A295' //bscTestnet
    },
    testnetCDai: {
      1: '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643',
      4: '0x6d7f0754ffeb405d23c51ce938289d4835be3b14',
      42: '0xf0d0eb522cfa50b716b3b1604c4f0fa6f04376ad'
    }
  },
  networks,
  solidity: {
    compilers: [
      {
        version: '0.8.6',
        settings: {
          optimizer: {
            enabled: optimizerEnabled,
            runs: 2000,
          },
          evmVersion: 'berlin',
        },
      },
    ],
  },
  external: {
    contracts: [
      {
        artifacts: "node_modules/@pooltogether/pooltogether-rng-contracts/build",
      },
    ]
  }
};

export default config;
