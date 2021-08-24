const { deployments } = require('hardhat');
const hardhat = require('hardhat');

const { getEvents } = require('../test/helpers/getEvents');
const ethers = require('ethers');
const { AddressZero } = ethers.constants;

const { BigNumber, utils } = ethers;

const toWei = (val) => ethers.utils.parseEther('' + val);

const debug = require('debug')('ptv3:deployTestPool');

async function deployTestPool({
  wallet,
  prizePeriodStart = 0,
  prizePeriodSeconds,
  maxExitFeeMantissa,
  creditLimit,
  creditRate,
  externalERC20Awards,
  poolType,
  overrides = { gasLimit: 20000000 },
}) {
  await deployments.fixture();
  const ERC20Mintable = await hre.ethers.getContractFactory('ERC20Mintable', wallet, overrides);

  debug('beforeEach deploy rng, forwarder etc...');

  /* = await deployContract(wallet, CTokenMock, [
    token.address, ethers.utils.parseEther('0.01')
  ], overrides)*/

  debug('Deploying Governor...');

  let governanceToken = await ERC20Mintable.deploy('Governance Token', 'GOV');

  let poolWithMultipleWinnersBuilderResult = await deployments.get(
    'PoolClaimableDrawPrizeStrategyBuilder',
  );
  let rngServiceMockResult = await deployments.get('RNGServiceMock');
  let tokenResult = await deployments.get('Dai');
  let cTokenResult = await deployments.get('cDai');
  let reserveResult = await deployments.get('Reserve');

  const reserve = await hardhat.ethers.getContractAt('Reserve', reserveResult.address, wallet);
  const token = await hardhat.ethers.getContractAt('ERC20Mintable', tokenResult.address, wallet);
  const cToken = await hardhat.ethers.getContractAt('CTokenMock', cTokenResult.address, wallet);
  const cTokenYieldSource = await hardhat.ethers.getContract('cDaiYieldSource', wallet);
  const poolBuilder = await hardhat.ethers.getContractAt(
    'PoolClaimableDrawPrizeStrategyBuilder',
    poolWithMultipleWinnersBuilderResult.address,
    wallet,
  );

  let linkToken = await ERC20Mintable.deploy('Link Token', 'LINK');
  let rngServiceMock = await hardhat.ethers.getContractAt(
    'RNGServiceMock',
    rngServiceMockResult.address,
    wallet,
  );
  await rngServiceMock.setRequestFee(linkToken.address, toWei('1'));

  const multipleWinnersConfig = {
    proxyAdmin: AddressZero,
    rngService: rngServiceMock.address,
    prizePeriodStart,
    prizePeriodSeconds,
    ticketName: 'Ticket',
    ticketSymbol: 'TICK',
    sponsorshipName: 'Sponsorship',
    sponsorshipSymbol: 'SPON',
    ticketCreditLimitMantissa: creditLimit,
    ticketCreditRateMantissa: creditRate,
    externalERC20Awards,
    prizeSplits: [],
  };

  const calculatorDrawSettings = {
    bitRangeValue: BigNumber.from(15),
    bitRangeSize: BigNumber.from(4),
    matchCardinality: BigNumber.from(5),
    pickCost: BigNumber.from(utils.parseEther('1')),
    distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
  };

  let prizePool;
  if (poolType == 'compound') {
    const compoundPrizePoolConfig = {
      cToken: cTokenResult.address,
      maxExitFeeMantissa,
    };
    let tx = await poolBuilder.createCompoundClaimableDrawPrizeStrategy(
      compoundPrizePoolConfig,
      multipleWinnersConfig,
      calculatorDrawSettings,
      await token.decimals(),
    );
    let events = await getEvents(poolBuilder, tx);
    let event = events[0];
    prizePool = await hardhat.ethers.getContractAt(
      'CompoundPrizePoolHarness',
      event.args.prizePool,
      wallet,
    );
  } else {
    throw new Error(`Unknown poolType: ${poolType}`);
  }

  debug('created prizePool: ', prizePool.address);

  let sponsorship = await hardhat.ethers.getContractAt(
    'contracts/token/ControlledToken.sol:ControlledToken',
    (await prizePool.tokens())[0],
    wallet,
  );
  let ticket = await hardhat.ethers.getContractAt('Ticket', (await prizePool.tokens())[1], wallet);

  debug(`sponsorship: ${sponsorship.address}, ticket: ${ticket.address}`);

  await prizePool.setCreditPlanOf(
    ticket.address,
    creditRate || toWei('0.1').div(prizePeriodSeconds),
    creditLimit || toWei('0.1'),
  );
  const prizeStrategyAddress = await prizePool.prizeStrategy();

  debug('Addresses: \n', {
    rngService: rngServiceMock.address,
    token: tokenResult.address,
    cToken: cTokenResult.address,
    ticket: ticket.address,
    prizePool: prizePool.address,
    sponsorship: sponsorship.address,
    prizeStrategy: prizeStrategyAddress,
    governanceToken: governanceToken.address,
  });

  const prizeStrategy = await hardhat.ethers.getContractAt(
    'ClaimableDrawPrizeStrategyHarness',
    prizeStrategyAddress,
    wallet,
  );

  debug(`Done!`);

  return {
    rngService: rngServiceMock,
    token,
    reserve,
    cToken,
    cTokenYieldSource,
    prizeStrategy,
    prizePool,
    ticket,
    sponsorship,
    governanceToken,
  };
}

module.exports = {
  deployTestPool,
};
