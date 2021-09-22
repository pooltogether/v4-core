const hardhat = require('hardhat')
const chalk = require('chalk');
const { expect } = require('chai');

require('../../helpers/chaiMatchers');

const { ethers, deployments } = hardhat;

const { AddressZero, MaxUint256 } = ethers.constants;

const debug = require('debug')('pt:PoolEnv.js');

const toWei = (val) => ethers.utils.parseEther('' + val);

function PoolEnv() {
  this.overrides = { gasLimit: 9500000 };

  this.ready = async function () {
    await deployments.fixture();
    this.wallets = await ethers.getSigners();
  };

  this.wallet = async function (id) {
    let wallet = this.wallets[id];
    return wallet;
  };

  this.yieldSource = async () => await ethers.getContract('MockYieldSource');

  this.token = async function (wallet) {
    const yieldSource = await this.yieldSource();
    const tokenAddress = await yieldSource.depositToken();
    return (await ethers.getContractAt('ERC20Mintable', tokenAddress)).connect(wallet);
  };

  this.ticket = async (wallet) => (await ethers.getContract('Ticket')).connect(wallet);

  this.prizePool = async (wallet) =>
    (await ethers.getContract('YieldSourcePrizePool')).connect(wallet);

  this.drawBeacon = async () => await ethers.getContract('DrawBeacon');

  this.drawHistory = async () => await ethers.getContract('DrawHistory');

  this.drawSettingsHistory = async () => await ethers.getContract('TsunamiDrawSettingsHistory');

  this.drawCalculator = async () => await ethers.getContract('TsunamiDrawCalculator');

  this.claimableDraw = async (wallet) =>
    (await ethers.getContract('ClaimableDraw')).connect(wallet);

  this.rng = async () => await ethers.getContract('RNGServiceStub');

  this.buyTickets = async function ({ user, tickets }) {
    debug(`Buying tickets...`);
    const owner = await this.wallet(0);
    let wallet = await this.wallet(user);

    debug('wallet is ', wallet.address);
    let token = await this.token(wallet);
    let ticket = await this.ticket(wallet);
    let prizePool = await this.prizePool(wallet);

    let amount = toWei(tickets);

    let balance = await token.balanceOf(wallet.address);

    if (balance.lt(amount)) {
      await token.mint(wallet.address, amount, this.overrides);
    }

    await token.approve(prizePool.address, amount, this.overrides);

    debug(`Depositing... (${wallet.address}, ${amount}, ${ticket.address}, ${AddressZero})`);

    await prizePool.depositTo(wallet.address, amount, this.overrides);

    debug(`Bought tickets`);
  };

  this.buyTicketsForClaimableDraw = async function ({ user, tickets, claimableDraw }) {
    debug(`Buying tickets...`);
    const owner = await this.wallet(0);
    let wallet = await this.wallet(user);

    debug('wallet is ', wallet.address);
    let token = await this.token(wallet);
    let ticket = await this.ticket(wallet);
    let prizePool = await this.prizePool(wallet);

    let amount = toWei(tickets);

    let balance = await token.balanceOf(wallet.address);
    if (balance.lt(amount)) {
      await token.mint(wallet.address, amount, this.overrides);
    }

    await token.approve(prizePool.address, amount, this.overrides);

    debug(`Depositing... (${wallet.address}, ${amount}, ${ticket.address}, ${AddressZero})`);

    await prizePool.depositTo(wallet.address, amount, this.overrides);

    debug(`Bought tickets`);
    ticket.transfer(claimableDraw, amount);

    debug(`Transfer tickets to claimableDraw`);
  };

  this.expectUserToHaveTickets = async function ({ user, tickets }) {
    let wallet = await this.wallet(user);
    let ticket = await this.ticket(wallet);
    let amount = toWei(tickets);
    expect(await ticket.balanceOf(wallet.address)).to.equalish(amount, '100000000000000000000');
  };

  this.expectUserToHaveTokens = async function ({ user, tokens }) {
    const wallet = await this.wallet(user);
    const token = await this.token(wallet);
    const amount = toWei(tokens);
    const balance = await token.balanceOf(wallet.address);
    debug(`expectUserToHaveTokens: ${balance.toString()}`);
    expect(balance).to.equal(amount);
  };

  this.claim = async function ({ user, drawId, picks, prize }) {
    const wallet = await this.wallet(user);
    const claimableDraw = await this.claimableDraw(wallet);
    const encoder = ethers.utils.defaultAbiCoder;
    const pickIndices = encoder.encode(['uint256[][]'], [[picks]]);
    await claimableDraw.claim(wallet.address, [drawId], pickIndices)
  }

  this.withdraw = async function ({ user, tickets }) {
    debug(`withdraw: user ${user}, tickets: ${tickets}`);
    let wallet = await this.wallet(user);
    let ticket = await this.ticket(wallet);
    let withdrawalAmount;

    if (!tickets) {
      withdrawalAmount = await ticket.balanceOf(wallet.address);
    } else {
      withdrawalAmount = toWei(tickets);
    }

    debug(`Withdrawing ${withdrawalAmount}...`)
    let prizePool = await this.prizePool(wallet);

    await prizePool.withdrawFrom(
      wallet.address,
      withdrawalAmount
    );

    debug('done withdraw');
  };

  this.poolAccrues = async function ({ tickets }) {
    debug(`poolAccrues(${tickets})...`);
    const yieldSource = await this.yieldSource();
    await yieldSource.yield(toWei(tickets));
  };

  this.draw = async function ({ randomNumber }) {
    const drawBeacon = await this.drawBeacon();
    const remainingTime = await drawBeacon.beaconPeriodRemainingSeconds();
    await ethers.provider.send('evm_increaseTime', [remainingTime.toNumber()]);
    await drawBeacon.startDraw();
    const rng = await this.rng();
    await rng.setRandomNumber(randomNumber);
    await drawBeacon.completeDraw();
  };

  this.expectDrawRandomNumber = async function ({ drawId, randomNumber }) {
    const drawHistory = await this.drawHistory();
    const draw = await drawHistory.getDraw(drawId);
    debug(`expectDrawRandomNumber draw: `, draw);
    expect(draw.winningRandomNumber).to.equal(randomNumber);
  };

  this.pushDrawSettings = async function ({
    drawId,
    bitRangeSize,
    drawStartTimestampOffset,
    drawEndTimestampOffset,
    matchCardinality,
    numberOfPicks,
    distributions,
    prize,
    maxPicksPerUser
  }) {
    const drawSettingsHistory = await this.drawSettingsHistory()

    const drawSettings = {
      bitRangeSize,
      matchCardinality,
      drawStartTimestampOffset,
      drawEndTimestampOffset,
      numberOfPicks,
      distributions,
      prize,
      maxPicksPerUser
    }

    await drawSettingsHistory.pushDrawSettings(drawId, drawSettings)
  }
}

module.exports = {
  PoolEnv,
};
