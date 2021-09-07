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

  const harnessDisabled = !!process.env.DISABLE_HARNESS;

  let { deployer, rng, admin, reserveRegistry, testnetCDai } = await getNamedAccounts();
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

  cyan(`\nDeploying RNGServiceStub...`)
  const rngServiceResult = await deploy('RNGServiceStub', {
    from: deployer
  })
  displayResult('RNGServiceStub', rngServiceResult)

  yellow('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~')
  yellow('CAUTION: Deploying Prize Pool in a front-runnable way!')

  cyan('\nDeploying MockYieldSource...')
  const mockYieldSourceResult = await deploy('MockYieldSource', {
    from: deployer,
    args: [
      'YIELD', 'YLD'
    ]
  })
  displayResult('MockYieldSource', mockYieldSourceResult)
  
  cyan('\nDeploying Registry...')
  const registryResult = await deploy('Registry', {
    from: deployer
  })
  displayResult('Registry', registryResult)

  cyan('\nDeploying Ticket...')
  const ticketResult = await deploy('Ticket', {
    from: deployer
  })
  displayResult('Ticket', ticketResult)

  cyan('\nDeploying YieldSourcePrizePool...')
  const yieldSourcePrizePoolResult = await deploy('YieldSourcePrizePool', {
    from: deployer
  })
  displayResult('YieldSourcePrizePool', yieldSourcePrizePoolResult)

  if (yieldSourcePrizePoolResult.newlyDeployed) {
    cyan('\nInitializing YieldSourcePrizePool....')
    const yieldSourcePrizePool = await ethers.getContract('YieldSourcePrizePool')
    await yieldSourcePrizePool.initializeYieldSourcePrizePool(
      registryResult.address,
      [ticketResult.address],
      ethers.utils.parseEther("0.5"),
      mockYieldSourceResult.address
    )
    green(`Initialized!`)
  }

  if (ticketResult.newlyDeployed) {
    cyan('\nInitializing Ticket....')
    const ticket = await ethers.getContract('Ticket')
    await ticket.initialize(
      "Ticket",
      "TICK",
      18,
      yieldSourcePrizePoolResult.address
    )
    green(`Initialized!`)
  }

  yellow('\nPrize Pool Setup Complete')
  yellow('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~')

  cyan('\nDeploying DrawBeacon...')
  const drawBeaconResult = await deploy('DrawBeacon', {
    from: deployer
  })
  displayResult('DrawBeacon', drawBeaconResult)

  cyan('\nDeploying DrawHistory...')
  const drawHistoryResult = await deploy('DrawHistory', {
    from: deployer,
    args: [
      
    ]
  })
  displayResult('DrawHistory', drawHistoryResult)

  if (drawBeaconResult.newlyDeployed) {
    cyan('\nInitializing DrawBeacon')
    const drawBeacon = await ethers.getContract('DrawBeacon')
    await drawBeacon.initialize(
      drawHistoryResult.address,
      rngServiceResult.address,
      parseInt('' + new Date().getTime() / 1000),
      120 // 2 minute intervals
    )
    green(`initialized!`)
  }
  
  if (drawHistoryResult.newlyDeployed) {
    const drawHistory = await ethers.getContract('DrawHistory')
    cyan('\nInitialzing DrawHistory...')
    await drawHistory.initialize(drawBeaconResult.address)
    green('Set!')
  }

  cyan('\nDeploying TsunamiDrawCalculator...')
  const drawCalculatorResult = await deploy('TsunamiDrawCalculator', {
    from: deployer
  })
  displayResult('TsunamiDrawCalculator', drawCalculatorResult)

  cyan('\nDeploying ClaimableDraw...')
  const claimableDrawResult = await deploy('ClaimableDraw', {
    from: deployer
  })
  displayResult('ClaimableDraw', claimableDrawResult)

  if (claimableDrawResult.newlyDeployed) {
    cyan('\nInitializing ClaimableDraw...')
    const claimableDraw = await ethers.getContract('ClaimableDraw')
    await claimableDraw.initialize(
      drawCalculatorResult.address,
      drawHistoryResult.address
    )
    green(`Initialized!`)
  }

  if (drawCalculatorResult.newlyDeployed) {
    cyan('\nInitializing TsunamiDrawCalculator...')
    const drawCalculator = await ethers.getContract('TsunamiDrawCalculator')
    await drawCalculator.initialize(
      ticketResult.address,
      deployer,
      claimableDrawResult.address
    )
    green(`Initialized!`)
  }

  dim('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  green('Contract Deployments Complete!');
  dim('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n');
};
