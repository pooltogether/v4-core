const chalk = require('chalk')
const hardhat = require('hardhat')
const { expect } = require('chai');
const { call } = require('../../helpers/call');
require('../../helpers/chaiMatchers');

const { ethers, deployments } = hardhat

const { AddressZero } = ethers.constants;

const debug = require('debug')('pt:PoolEnv.js');

const toWei = (val) => ethers.utils.parseEther('' + val);
const fromWei = (val) => ethers.utils.formatEther('' + val);

function PoolEnv() {  
  this.overrides = { gasLimit: 9500000 };

  this.ready = async function () {
    await deployments.fixture()
    this.wallets = await ethers.getSigners()
  }

  this.wallet = async function (id) {
    let wallet = this.wallets[id];
    return wallet;
  };

  this.yieldSource = async () => await ethers.getContract('MockYieldSource')

  this.token = async function (wallet) {
    const yieldSource = await this.yieldSource()
    const tokenAddress = await yieldSource.depositToken()
    return (await ethers.getContractAt('ERC20Mintable', tokenAddress)).connect(wallet)
  }

  this.ticket = async (wallet) => (await ethers.getContract('Ticket')).connect(wallet)

  this.prizePool = async (wallet) => (await ethers.getContract('YieldSourcePrizePool')).connect(wallet)

  this.drawBeacon = async () => await ethers.getContract('DrawBeacon')

  this.drawHistory = async () => await ethers.getContract('DrawHistory')

  this.drawCalculator = async () => await ethers.getContract('TsunamiDrawCalculator')

  this.claimableDraw = async (wallet) => (await ethers.getContract('ClaimableDraw')).connect(wallet)

  this.rng = async () => await ethers.getContract('RNGServiceStub')

  this.buyTickets = async function ({ user, tickets }) {
    debug(`Buying tickets...`);
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

    await prizePool.depositTo(
      wallet.address,
      amount,
      ticket.address,
      AddressZero,
      this.overrides,
    );

    debug(`Bought tickets`);
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
    const balance = await token.balanceOf(wallet.address)
    debug(`expectUserToHaveTokens: ${balance.toString()}`)
    expect(balance).to.equal(amount);
  };

  this.claim = async function ({ user, drawId, picks, prize }) {
    const wallet = await this.wallet(user);
    const claimableDraw = await this.claimableDraw(wallet)
    const token = await this.token(wallet)
    await token.mint(claimableDraw.address, toWei(prize || 10))
    const encoder = ethers.utils.defaultAbiCoder
    const pickIndices = encoder.encode(['uint256[][]'], [[picks]]);
    await claimableDraw.claim(wallet.address, [[drawId]], [(await this.drawCalculator()).address], [pickIndices])
  }

  this.withdrawInstantly = async function ({ user, tickets }) {
    debug(`withdrawInstantly: user ${user}, tickets: ${tickets}`);
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
    await prizePool.withdrawInstantlyFrom(
      wallet.address,
      withdrawalAmount,
      ticket.address,
      withdrawalAmount,
    );
    debug('done withdraw instantly');
  };

  this.poolAccrues = async function ({ tickets }) {
    debug(`poolAccrues(${tickets})...`);
    const yieldSource = await this.yieldSource()
    await yieldSource.yield(toWei(tickets));
  };

  this.draw = async function ({ randomNumber }) {
    const drawBeacon = await this.drawBeacon()
    const remainingTime = await drawBeacon.drawPeriodRemainingSeconds()
    await ethers.provider.send('evm_increaseTime', [remainingTime.toNumber()])
    await drawBeacon.startDraw()
    const rng = await this.rng()
    await rng.setRandomNumber(randomNumber)
    await drawBeacon.completeDraw()
  };

  this.expectDrawRandomNumber = async function({ drawId, randomNumber }) {
    const drawHistory = await this.drawHistory()
    const draw = await drawHistory.getDraw(drawId)
    debug(`expectDrawRandomNumber draw: `, draw)
    expect(draw.winningRandomNumber).to.equal(randomNumber)
  }

  this.setDrawSettings = async function ({
    drawId,
    bitRangeSize,
    matchCardinality,
    pickCost,
    distributions,
    prize
  }) {
    const drawCalculator = await this.drawCalculator()
    const drawSettings = {
      bitRangeSize,
      matchCardinality,
      pickCost,
      distributions,
      prize,
    }
    await drawCalculator.setDrawSettings(drawId, drawSettings)
  }

  /*
  this.expectUserToHaveTokens = async function ({ user, tokens }) {
    let wallet = await this.wallet(user);
    let token = await this.token(wallet);
    let amount = toWei(tokens);
    expect(await token.balanceOf(wallet.address)).to.equal(amount);
  };

  this.expectUserToHaveGovernanceTokens = async function ({ user, tokens }) {
    let wallet = await this.wallet(user);
    let governanceToken = await this.governanceToken(wallet);
    let amount = toWei(tokens);
    expect(await governanceToken.balanceOf(wallet.address)).to.equal(amount);
  };

  this.expectUserToHaveSponsorship = async function ({ user, sponsorship }) {
    let wallet = await this.wallet(user);
    let sponsorshipContract = await this.sponsorship(wallet);
    let amount = toWei(sponsorship);
    expect(await sponsorshipContract.balanceOf(wallet.address)).to.equal(amount);
  };

  this.poolAccrues = async function ({ tickets }) {
    debug(`poolAccrues(${tickets.toString()})...`);
    await this.env.cToken.accrueCustom(toWei(tickets));
  };

  this.expectPoolToHavePrize = async function ({ tickets }) {
    let ticketInterest = await call(this._prizePool, 'captureAwardBalance');
    await expect(ticketInterest).to.equal(toWei(tickets));
  };

  this.expectUserToHaveCredit = async function ({ user, credit }) {
    let wallet = await this.wallet(user);
    let ticket = await this.ticket(wallet);
    let prizePool = await this.prizePool(wallet);
    let ticketInterest = await call(prizePool, 'balanceOfCredit', wallet.address, ticket.address);
    debug(`expectUserToHaveCredit ticketInterest ${ticketInterest.toString()}`);
    expect(ticketInterest).to.equalish(toWei(credit), '100000000000000000000');
  };

  this.expectUserToHaveExternalAwardAmount = async function ({ user, externalAward, amount }) {
    let wallet = await this.wallet(user);
    expect(await this.externalERC20Awards[externalAward].balanceOf(wallet.address)).to.equal(
      toWei(amount),
    );
  };

  this.startAward = async function () {
    debug(`startAward`);

    let endTime = await this._prizeStrategy.prizePeriodEndAt();

    await this.setCurrentTime(endTime);

    await this.env.prizeStrategy.startAward(this.overrides);
  };

  this.completeAward = async function ({ token }) {
    // let randomNumber = ethers.utils.hexlify(ethers.utils.zeroPad(ethers.BigNumber.from('' + token), 32))
    await this.env.rngService.setRandomNumber(token, this.overrides);

    debug(`awardPrizeToToken Completing award...`);
    await this.env.prizeStrategy.completeAward(this.overrides);

    debug('award completed');
  };

  this.expectRevertWith = async function (promise, msg) {
    await expect(promise).to.be.revertedWith(msg);
  };

  this.awardPrize = async function () {
    await this.awardPrizeToToken({ token: 0 });
  };

  this.awardPrizeToToken = async function ({ token }) {
    await this.startAward();
    await this.completeAward({ token });
  };

  this.transferTickets = async function ({ user, tickets, to }) {
    let wallet = await this.wallet(user);
    let ticket = await this.ticket(wallet);
    let toWallet = await this.wallet(to);
    await ticket.transfer(toWallet.address, toWei(tickets));
  };

  this.draw = async function ({ token }) {
    let winner = await this.ticket.draw(token);
    debug(`draw(${token}) = ${winner}`);
  };

  this.withdrawInstantly = async function ({ user, tickets }) {
    debug(`withdrawInstantly: user ${user}, tickets: ${tickets}`);
    let wallet = await this.wallet(user);
    let ticket = await this.ticket(wallet);
    let withdrawalAmount;
    if (!tickets) {
      withdrawalAmount = await ticket.balanceOf(wallet.address);
    } else {
      withdrawalAmount = toWei(tickets);
    }
    let prizePool = await this.prizePool(wallet);
    await prizePool.withdrawInstantlyFrom(
      wallet.address,
      withdrawalAmount,
      ticket.address,
      toWei('1000'),
    );
    debug('done withdraw instantly');
  };

  this.balanceOfTickets = async function ({ user }) {
    let wallet = await this.wallet(user);
    let ticket = await this.ticket(wallet);
    return fromWei(await ticket.balanceOf(wallet.address));
  };

  this.addExternalAwardERC721 = async function ({ user, tokenId }) {
    let wallet = await this.wallet(user);
    let prizePool = await this.prizePool(wallet);
    let prizeStrategy = await this.prizeStrategy(wallet);
    await this.externalErc721Award.mint(prizePool.address, tokenId);
    await prizeStrategy.addExternalErc721Award(this.externalErc721Award.address, [tokenId]);
  };

  this.expectUserToHaveExternalAwardToken = async function ({ user, tokenId }) {
    let wallet = await this.wallet(user);
    expect(await this.externalErc721Award.ownerOf(tokenId)).to.equal(wallet.address);
  };
  */
}

module.exports = {
  PoolEnv,
};
