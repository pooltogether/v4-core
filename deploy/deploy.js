const { deploy1820 } = require('deploy-eip-1820');
const chalk = require('chalk');

function dim() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.dim.call(chalk, ...arguments));
  }
}

function cyan() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.cyan.call(chalk, ...arguments));
  }
}

function yellow() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.yellow.call(chalk, ...arguments));
  }
}

function green() {
  if (!process.env.HIDE_DEPLOY_LOG) {
    console.log(chalk.green.call(chalk, ...arguments));
  }
}

function displayResult(name, result) {
  if (!result.newlyDeployed) {
    yellow(`Re-used existing ${name} at ${result.address}`);
  } else {
    green(`${name} deployed at ${result.address}`);
  }
}

const chainName = (chainId) => {
  switch (chainId) {
    case 1:
      return 'Mainnet';
    case 3:
      return 'Ropsten';
    case 4:
      return 'Rinkeby';
    case 5:
      return 'Goerli';
    case 42:
      return 'Kovan';
    case 56:
      return 'Binance Smart Chain';
    case 77:
      return 'POA Sokol';
    case 97:
      return 'Binance Smart Chain (testnet)';
    case 99:
      return 'POA';
    case 100:
      return 'xDai';
    case 137:
      return 'Matic';
    case 31337:
      return 'HardhatEVM';
    case 80001:
      return 'Matic (Mumbai)';
    default:
      return 'Unknown';
  }
};

module.exports = async (hardhat) => {
  const { getNamedAccounts, deployments, getChainId, ethers } = hardhat;
  const { deploy } = deployments;

  let { deployer } = await getNamedAccounts();
  const chainId = parseInt(await getChainId(), 10);

  // 31337 is unit testing, 1337 is for coverage
  const isTestEnvironment = chainId === 31337 || chainId === 1337;

  const signer = await ethers.provider.getSigner(deployer);

  dim('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  dim('PoolTogether Pool Contracts - Deploy Script');
  dim('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n');

  dim(`Network: ${chainName(chainId)} (${isTestEnvironment ? 'local' : 'remote'})`);
  dim(`Deployer: ${deployer}`);

  await deploy1820(signer);

  cyan(`\nDeploying RNGServiceStub...`);
  const rngServiceResult = await deploy('RNGServiceStub', {
    from: deployer,
  });

  displayResult('RNGServiceStub', rngServiceResult);

  yellow('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  yellow('CAUTION: Deploying Prize Pool in a front-runnable way!');

  cyan('\nDeploying MockYieldSource...');
  const mockYieldSourceResult = await deploy('MockYieldSource', {
    from: deployer,
    args: ['YIELD', 'YLD'],
  });

  displayResult('MockYieldSource', mockYieldSourceResult);

  cyan('\nDeploying YieldSourcePrizePool...');
  const yieldSourcePrizePoolResult = await deploy('YieldSourcePrizePool', {
    from: deployer,
    args: [deployer, mockYieldSourceResult.address],
  });

  displayResult('YieldSourcePrizePool', yieldSourcePrizePoolResult);

  cyan('\nDeploying Ticket...');
  const ticketResult = await deploy('Ticket', {
    from: deployer,
    args: ['Ticket', 'TICK', 18, yieldSourcePrizePoolResult.address],
  });

  displayResult('Ticket', ticketResult);

  cyan('\nsetTicket for YieldSourcePrizePool...');

  const yieldSourcePrizePool = await ethers.getContract('YieldSourcePrizePool');

  const setTicketResult = await yieldSourcePrizePool.setTicket(ticketResult.address);

  displayResult('setTicket', setTicketResult);

  yellow('\nPrize Pool Setup Complete');
  yellow('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');

  const cardinality = 8;

  cyan('\nDeploying DrawHistory...');
  const drawHistoryResult = await deploy('DrawHistory', {
    from: deployer,
    args: [
      deployer,
      cardinality
    ]
  });
  displayResult('DrawHistory', drawHistoryResult);

  cyan('\nDeploying TsunamiDrawSettingsHistory...');
  const tsunamiDrawSettindsHistoryResult = await deploy('TsunamiDrawSettingsHistory', {
    from: deployer,
    args: [
      deployer,
      cardinality
    ]
  });
  displayResult('TsunamiDrawSettingsHistory', tsunamiDrawSettindsHistoryResult);

  cyan('\nDeploying DrawBeacon...');
  const drawBeaconResult = await deploy('DrawBeacon', {
    from: deployer,
    args: [
      deployer,
      drawHistoryResult.address,
      rngServiceResult.address,
      1,
      parseInt('' + new Date().getTime() / 1000),
      120, // 2 minute intervals
    ],
  });

  displayResult('DrawBeacon', drawBeaconResult);

  cyan('\nSet DrawBeacon as manager for DrawHistory...');
  const drawHistory = await ethers.getContract('DrawHistory');
  await drawHistory.setManager(drawBeaconResult.address);
  green('DrawBeacon manager set!');

  cyan('\nDeploying TsunamiDrawCalculator...');
  const drawCalculatorResult = await deploy('TsunamiDrawCalculator', {
    from: deployer,
    args: [deployer, ticketResult.address, drawHistoryResult.address, tsunamiDrawSettindsHistoryResult.address],
  });
  displayResult('TsunamiDrawCalculator', drawCalculatorResult);

  cyan('\nDeploying ClaimableDraw...');
  const claimableDrawResult = await deploy('ClaimableDraw', {
    from: deployer,
    args: [deployer, ticketResult.address, drawCalculatorResult.address],
  });
  displayResult('ClaimableDraw', claimableDrawResult);

  dim('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  green('Contract Deployments Complete!');
  dim('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n');
};
