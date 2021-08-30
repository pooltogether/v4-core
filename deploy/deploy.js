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

  dim(`network: ${chainName(chainId)} (${isTestEnvironment ? 'local' : 'remote'})`);
  dim(`deployer: ${deployer}`);
  if (!admin) {
    admin = signer._address;
  }
  dim('admin:', admin);

  await deploy1820(signer);

  let cDaiAddress = testnetCDai;
  if (isTestEnvironment) {
    cyan('\nDeploying RNGService...');
    const rngServiceMockResult = await deploy('RNGServiceMock', {
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
    rng = rngServiceMockResult.address;

    cyan('\nDeploying Dai...');
    const daiResult = await deploy('Dai', {
      args: ['DAI Test Token', 'DAI'],
      contract: 'ERC20Mintable',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });

    cyan('\nDeploying cDai...');
    // should be about 20% APR
    let supplyRate = '8888888888888';
    const cDaiResult = await deploy('cDai', {
      args: [daiResult.address, supplyRate],
      contract: 'CTokenMock',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
    cDaiAddress = cDaiResult.address;

    // Display Contract Addresses
    dim('\nLocal Contract Deployments;\n');
    dim('  - RNGService:       ', rng);
    dim('  - Dai:              ', daiResult.address);
  }

  if (cDaiAddress) {
    cyan('\nDeploy cDaiYieldSource...');
    const cDaiYieldSourceResult = await deploy('cDaiYieldSource', {
      args: [cDaiAddress],
      contract: 'CTokenYieldSource',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
    displayResult('cDaiYieldSource', cDaiYieldSourceResult);
  }

  // cyan(`\nDeploying TokenFaucetProxyFactory...`)
  // const tokenFaucetProxyFactoryResult = await deploy("TokenFaucetProxyFactory", {
  //   from: deployer
  // })
  // displayResult('TokenFaucetProxyFactory', tokenFaucetProxyFactoryResult)

  cyan(`\nDeploying ReserveRegistry...`);
  if (!reserveRegistry) {
    // if not set by named config
    cyan(`\nDeploying Reserve...`);
    const reserveResult = await deploy('Reserve', {
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
    displayResult('Reserve', reserveResult);

    const reserveContract = await hardhat.ethers.getContractAt(
      'Reserve',
      reserveResult.address,
      signer,
    );
    if (admin !== deployer) {
      await reserveContract.transferOwnership(admin);
    }

    const reserveRegistryResult = await deploy('ReserveRegistry', {
      contract: 'Registry',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
    displayResult('ReserveRegistry', reserveRegistryResult);

    const reserveRegistryContract = await hardhat.ethers.getContractAt(
      'Registry',
      reserveRegistryResult.address,
      signer,
    );
    // if (await reserveRegistryContract.lookup() != reserveResult.address) {
    //   await reserveRegistryContract.register(reserveResult.address)
    // }
    if (admin !== deployer) {
      await reserveRegistryContract.transferOwnership(admin);
    }

    reserveRegistry = reserveRegistryResult.address;
  } else {
    yellow(`Using existing reserve registry ${reserveRegistry}`);
  }

  /* ------------------------------------ */
  // CompoundPrizePoolProxyFactory
  /* ------------------------------------ */
  cyan('\nDeploying CompoundPrizePoolProxyFactory...');
  let compoundPrizePoolProxyFactoryResult;
  if (isTestEnvironment && !harnessDisabled) {
    compoundPrizePoolProxyFactoryResult = await deploy('CompoundPrizePoolProxyFactory', {
      contract: 'CompoundPrizePoolHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
  } else {
    compoundPrizePoolProxyFactoryResult = await deploy('CompoundPrizePoolProxyFactory', {
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
  }
  displayResult('CompoundPrizePoolProxyFactory', compoundPrizePoolProxyFactoryResult);

  /* ==================================== */
  //            PROXY FACTORIES
  /* ==================================== */

  /* ------------------------------------ */
  // ControlledTokenProxyFactory
  /* ------------------------------------ */
  cyan('\nDeploying ControlledTokenProxyFactory...');
  const controlledTokenProxyFactoryResult = await deploy('ControlledTokenProxyFactory', {
    contract: 'ControlledTokenDeployerProxyFactory',
    from: deployer,
    skipIfAlreadyDeployed: true,
  });
  displayResult('ControlledTokenProxyFactory', controlledTokenProxyFactoryResult);

  cyan('\nDeploying TicketProxyFactory...');
  const ticketProxyFactoryResult = await deploy('TicketProxyFactory', {
    from: deployer,
    skipIfAlreadyDeployed: true,
  });
  displayResult('TicketProxyFactory', ticketProxyFactoryResult);

  /* ------------------------------------ */
  // TsunamiDrawCalculatorProxyFactory
  /* ------------------------------------ */
  let tsunamiDrawCalculatorProxyFactory;
  if (isTestEnvironment && !harnessDisabled) {
    cyan('\nDeploying TsunamiDrawCalculatorProxyFactory...');
    tsunamiDrawCalculatorProxyFactory = await deploy('TsunamiDrawCalculatorProxyFactory', {
      contract: 'TsunamiDrawCalculatorHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
  } else {
    cyan('\nDeploying TsunamiDrawCalculatorProxyFactory...');
    tsunamiDrawCalculatorProxyFactory = await deploy('TsunamiDrawCalculatorProxyFactory', {
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
  }
  displayResult('ClaimableDrawProxyFactory', tsunamiDrawCalculatorProxyFactory);

  /* ------------------------------------ */
  // ClaimableDrawProxyFactory
  /* ------------------------------------ */
  let claimableDrawProxyFactoryResult;
  if (isTestEnvironment && !harnessDisabled) {
    cyan('\nDeploying StakePrizePoolHarnessProxyFactory...');
    claimableDrawProxyFactoryResult = await deploy('ClaimableDrawProxyFactory', {
      contract: 'ClaimableDrawHarnessProxyFactory',
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
  } else {
    cyan('\nDeploying StakePrizePoolProxyFactory...');
    claimableDrawProxyFactoryResult = await deploy('ClaimableDrawProxyFactory', {
      from: deployer,
      skipIfAlreadyDeployed: true,
    });
  }
  displayResult('ClaimableDrawProxyFactory', claimableDrawProxyFactoryResult);

  /* ------------------------------------ */
  // ClaimableDrawPrizeStrategyProxyFactory
  /* ------------------------------------ */
  let claimableDrawPrizeStrategyProxyFactoryResult;
  cyan('\nDeploying ClaimableDrawPrizeStrategyProxyFactory...');
  if (isTestEnvironment && !harnessDisabled) {
    claimableDrawPrizeStrategyProxyFactoryResult = await deploy(
      'ClaimableDrawPrizeStrategyProxyFactory',
      {
        contract: 'ClaimableDrawPrizeStrategyHarnessProxyFactory',
        from: deployer,
        skipIfAlreadyDeployed: true,
      },
    );
  } else {
    claimableDrawPrizeStrategyProxyFactoryResult = await deploy(
      'ClaimableDrawPrizeStrategyProxyFactory',
      {
        from: deployer,
        skipIfAlreadyDeployed: true,
      },
    );
  }
  displayResult(
    'ClaimableDrawPrizeStrategyProxyFactory',
    claimableDrawPrizeStrategyProxyFactoryResult,
  );

  /* ==================================== */
  //                BUILDERS
  /* ==================================== */

  /* ------------------------------------ */
  // ControlledTokenBuilder
  /* ------------------------------------ */
  cyan('\nDeploying ControlledTokenBuilder...');
  const controlledTokenBuilderResult = await deploy('ControlledTokenBuilder', {
    args: [controlledTokenProxyFactoryResult.address, ticketProxyFactoryResult.address],
    from: deployer,
    skipIfAlreadyDeployed: true,
  });
  displayResult('ControlledTokenBuilder', controlledTokenBuilderResult);

  /* ------------------------------------ */
  // ClaimableDrawPrizeStrategyBuilder
  /* ------------------------------------ */
  cyan('\nDeploying ClaimableDrawPrizeStrategyBuilder...');
  const claimableDrawPrizeStrategtBuilderResult = await deploy(
    'ClaimableDrawPrizeStrategyBuilder',
    {
      args: [
        claimableDrawProxyFactoryResult.address,
        claimableDrawPrizeStrategyProxyFactoryResult.address,
        tsunamiDrawCalculatorProxyFactory.address,
        controlledTokenBuilderResult.address,
      ],
      from: deployer,
      skipIfAlreadyDeployed: true,
    },
  );
  displayResult('ClaimableDrawPrizeStrategyBuilder', claimableDrawPrizeStrategtBuilderResult);

  /* ------------------------------------ */
  // PoolClaimableDrawPrizeStrategyBuilder
  /* ------------------------------------ */
  cyan('\nDeploying PoolClaimableDrawPrizeStrategyBuilder...');
  const poolClaimableDrawPrizeStrategyBuilder = await deploy(
    'PoolClaimableDrawPrizeStrategyBuilder',
    {
      args: [
        reserveRegistry,
        compoundPrizePoolProxyFactoryResult.address,
        claimableDrawPrizeStrategtBuilderResult.address,
      ],
      from: deployer,
      skipIfAlreadyDeployed: true,
    },
  );
  displayResult('PoolClaimableDrawPrizeStrategyBuilder', poolClaimableDrawPrizeStrategyBuilder);

  dim('\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~');
  green('Contract Deployments Complete!');
  dim('~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n');
};
