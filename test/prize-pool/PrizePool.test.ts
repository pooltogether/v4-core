import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { BigNumber, constants, Contract, utils } from 'ethers';
import { ethers, artifacts } from 'hardhat';

import { call } from '../helpers/call';

const { AddressZero, MaxUint256 } = constants;
const { getContractFactory, getSigners, Wallet } = ethers;
const { parseEther: toWei } = utils;

const debug = require('debug')('ptv3:PrizePool.test');

const NFT_TOKEN_ID = 1;

describe('PrizePool', function () {
  let contractsOwner: SignerWithAddress;
  let wallet2: SignerWithAddress;
  let prizeStrategyManager: SignerWithAddress;

  // Set as `any` cause types are conflicting between the different path for ethers
  let prizePool: any;
  let prizePool2: any;

  let yieldSourceStub: MockContract;

  let depositToken: Contract;
  let erc20Token: Contract;
  let erc721Token: Contract;
  let erc721tokenMock: MockContract;

  let ticket: Contract;

  let compLike: MockContract;

  const depositTokenIntoPrizePool = async (
    walletAddress: string,
    amount: BigNumber,
    token: Contract = depositToken,
    pool: Contract = prizePool,
  ) => {
    await yieldSourceStub.mock.supplyTokenTo.withArgs(amount, pool.address).returns();

    await token.approve(pool.address, amount);
    await token.mint(walletAddress, amount);

    if (token.address === depositToken.address) {
      return await pool.depositTo(walletAddress, amount);
    } else {
      return await token.transfer(pool.address, amount);
    }
  };

  const depositNftIntoPrizePool = async (walletAddress: string) => {
    await erc721Token.mint(walletAddress, NFT_TOKEN_ID);
    await erc721Token.transferFrom(walletAddress, prizePool.address, NFT_TOKEN_ID);
  };

  beforeEach(async () => {
    [contractsOwner, wallet2, prizeStrategyManager] = await getSigners();
    debug(`using wallet ${contractsOwner.address}`);

    debug('mocking tokens...');
    const ERC20MintableContract = await getContractFactory('ERC20Mintable', contractsOwner);
    depositToken = await ERC20MintableContract.deploy('Token', 'TOKE');
    erc20Token = await ERC20MintableContract.deploy('Token', 'TOKE');

    const ICompLike = await artifacts.readArtifact('ICompLike');
    compLike = await deployMockContract(contractsOwner as Signer, ICompLike.abi);

    const ERC721MintableContract = await getContractFactory('ERC721Mintable', contractsOwner);
    erc721Token = await ERC721MintableContract.deploy();

    const IERC721 = await artifacts.readArtifact('IERC721');
    erc721tokenMock = await deployMockContract(contractsOwner as Signer, IERC721.abi);

    const YieldSourceStub = await artifacts.readArtifact('YieldSourceStub');
    yieldSourceStub = await deployMockContract(contractsOwner as Signer, YieldSourceStub.abi);
    await yieldSourceStub.mock.depositToken.returns(depositToken.address);

    const PrizePoolHarness = await getContractFactory('PrizePoolHarness', contractsOwner);
    prizePool = await PrizePoolHarness.deploy(contractsOwner.address, yieldSourceStub.address);

    const Ticket = await getContractFactory('Ticket');
    ticket = await Ticket.deploy('name', 'SYMBOL', 18, prizePool.address);
  });

  describe('constructor()', () => {
    it('should fire the events', async () => {
      const tx = prizePool.deployTransaction;

      await expect(tx).to.emit(prizePool, 'LiquidityCapSet').withArgs(MaxUint256);

      await expect(prizePool.setPrizeStrategy(prizeStrategyManager.address))
        .to.emit(prizePool, 'PrizeStrategySet')
        .withArgs(prizeStrategyManager.address);

      await expect(prizePool.setTicket(ticket.address))
        .to.emit(prizePool, 'TicketSet')
        .withArgs(ticket.address);
    });
  });

  describe('with a mocked prize pool', () => {
    beforeEach(async () => {
      await prizePool.setPrizeStrategy(prizeStrategyManager.address);
      await prizePool.setBalanceCap(ticket.address, MaxUint256);
      await prizePool.setTicket(ticket.address);
    });

    describe('constructor()', () => {
      it('should set all the vars', async () => {
        expect(await prizePool.token()).to.equal(depositToken.address);
      });

      it('should reject invalid params', async () => {
        const PrizePoolHarness = await getContractFactory('PrizePoolHarness', contractsOwner);
        prizePool2 = await PrizePoolHarness.deploy(contractsOwner.address, yieldSourceStub.address);

        await expect(prizePool2.setTicket(AddressZero)).to.be.revertedWith(
          'PrizePool/ticket-not-zero-address',
        );
      });
    });

    describe('depositTo()', () => {
      it('should revert when deposit exceeds liquidity cap', async () => {
        const amount = toWei('1');
        const liquidityCap = toWei('1000');

        await depositTokenIntoPrizePool(contractsOwner.address, liquidityCap);

        await prizePool.setLiquidityCap(liquidityCap);

        await expect(
          prizePool.depositTo(wallet2.address, amount),
        ).to.be.revertedWith('PrizePool/exceeds-liquidity-cap');
      });

      it('should revert when user deposit exceeds ticket balance cap', async () => {
        const amount = toWei('1');
        const balanceCap = toWei('50000');

        await prizePool.setBalanceCap(ticket.address, balanceCap);
        await depositTokenIntoPrizePool(contractsOwner.address, balanceCap);

        await expect(depositTokenIntoPrizePool(contractsOwner.address, amount)).to.be.revertedWith(
          'PrizePool/exceeds-balance-cap',
        );
      });
    });

    describe('captureAwardBalance()', () => {
      it('should handle when the balance is less than the collateral', async () => {
        await depositTokenIntoPrizePool(contractsOwner.address, toWei('100'));

        await yieldSourceStub.mock.balanceOfToken
          .withArgs(prizePool.address)
          .returns(toWei('99.9999'));

        expect(await prizePool.awardBalance()).to.equal(toWei('0'));
      });

      it('should handle the situ when the total accrued interest is less than the captured total', async () => {
        await depositTokenIntoPrizePool(contractsOwner.address, toWei('100'));

        await yieldSourceStub.mock.balanceOfToken.withArgs(prizePool.address).returns(toWei('110'));

        // first capture the 10 tokens
        await prizePool.captureAwardBalance();

        await yieldSourceStub.mock.balanceOfToken
          .withArgs(prizePool.address)
          .returns(toWei('109.999'));

        // now try to capture again
        await expect(prizePool.captureAwardBalance()).to.not.emit(prizePool, 'AwardCaptured');
      });

      it('should track the yield less the total token supply', async () => {
        await depositTokenIntoPrizePool(contractsOwner.address, toWei('100'));

        await yieldSourceStub.mock.balanceOfToken.withArgs(prizePool.address).returns(toWei('110'));

        await expect(prizePool.captureAwardBalance())
          .to.emit(prizePool, 'AwardCaptured')
          .withArgs(toWei('10'));
        expect(await prizePool.awardBalance()).to.equal(toWei('10'));
      });
    });

    describe('withdrawFrom()', () => {
      it('should allow a user to withdraw instantly', async () => {
        let amount = toWei('10');

        await depositTokenIntoPrizePool(contractsOwner.address, amount);

        await yieldSourceStub.mock.redeemToken.withArgs(amount).returns(amount);

        await expect(prizePool.withdrawFrom(contractsOwner.address, amount))
          .to.emit(prizePool, 'Withdrawal')
          .withArgs(contractsOwner.address, contractsOwner.address, ticket.address, amount, amount);
      });
    });

    describe('balance()', () => {
      it('should return zero if no deposits have been made', async () => {
        const balance = toWei('11');

        await yieldSourceStub.mock.balanceOfToken.withArgs(prizePool.address).returns(balance);

        expect((await call(prizePool, 'balance')).toString()).to.equal(balance);
      });
    });

    describe('setPrizeStrategy()', () => {
      it('should allow the owner to swap the prize strategy', async () => {
        const randomWallet = Wallet.createRandom();

        await expect(prizePool.setPrizeStrategy(randomWallet.address))
          .to.emit(prizePool, 'PrizeStrategySet')
          .withArgs(randomWallet.address);

        expect(await prizePool.prizeStrategy()).to.equal(randomWallet.address);
      });

      it('should not allow anyone else to change the prize strategy', async () => {
        await expect(
          prizePool.connect(wallet2 as Signer).setPrizeStrategy(wallet2.address),
        ).to.be.revertedWith('Ownable/caller-not-owner');
      });
    });

    describe('setBalanceCap', () => {
      it('should allow the owner to set the balance cap', async () => {
        const balanceCap = toWei('50000');

        await expect(prizePool.setBalanceCap(ticket.address, balanceCap))
          .to.emit(prizePool, 'BalanceCapSet')
          .withArgs(ticket.address, balanceCap);

        expect(await prizePool.balanceCap(ticket.address)).to.equal(balanceCap);
      });

      it('should not allow anyone else to call', async () => {
        prizePool2 = prizePool.connect(wallet2 as Signer);

        await expect(prizePool2.setBalanceCap(ticket.address, toWei('50000'))).to.be.revertedWith(
          'Ownable/caller-not-owner',
        );
      });
    });

    describe('setLiquidityCap', () => {
      it('should allow the owner to set the liquidity cap', async () => {
        const liquidityCap = toWei('1000');

        await expect(prizePool.setLiquidityCap(liquidityCap))
          .to.emit(prizePool, 'LiquidityCapSet')
          .withArgs(liquidityCap);

        expect(await prizePool.liquidityCap()).to.equal(liquidityCap);
      });

      it('should not allow anyone else to call', async () => {
        prizePool2 = prizePool.connect(wallet2 as Signer);

        await expect(prizePool2.setLiquidityCap(toWei('1000'))).to.be.revertedWith(
          'Ownable/caller-not-owner',
        );
      });
    });

    describe('compLikeDelegate()', () => {
      it('should delegate votes', async () => {
        await compLike.mock.balanceOf.withArgs(prizePool.address).returns('1');
        await compLike.mock.delegate.withArgs(wallet2.address).revertsWithReason('hello');

        await expect(
          prizePool.compLikeDelegate(compLike.address, wallet2.address),
        ).to.be.revertedWith('hello');
      });

      it('should only allow the owner to delegate', async () => {
        await expect(
          prizePool.connect(wallet2 as Signer).compLikeDelegate(compLike.address, wallet2.address),
        ).to.be.revertedWith('Ownable/caller-not-owner');
      });

      it('should not delegate if the balance is zero', async () => {
        await compLike.mock.balanceOf.withArgs(prizePool.address).returns('0');
        await prizePool.compLikeDelegate(compLike.address, wallet2.address);
      });
    });
  });

  describe('awardExternalERC20()', () => {
    beforeEach(async () => {
      await prizePool.setPrizeStrategy(prizeStrategyManager.address);
    });

    it('should exit early when amount = 0', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc20Token.address).returns(true);

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .awardExternalERC20(contractsOwner.address, erc20Token.address, 0),
      ).to.not.emit(prizePool, 'AwardedExternalERC20');
    });

    it('should only allow the prizeStrategy to award external ERC20s', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc20Token.address).returns(true);

      let prizePool2 = prizePool.connect(wallet2 as Signer);

      await expect(
        prizePool2.awardExternalERC20(contractsOwner.address, wallet2.address, toWei('10')),
      ).to.be.revertedWith('PrizePool/only-prizeStrategy');
    });

    it('should allow arbitrary tokens to be transferred', async () => {
      const amount = toWei('10');

      await yieldSourceStub.mock.canAwardExternal.withArgs(erc20Token.address).returns(true);

      await depositTokenIntoPrizePool(contractsOwner.address, amount, erc20Token);

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .awardExternalERC20(contractsOwner.address, erc20Token.address, amount),
      )
        .to.emit(prizePool, 'AwardedExternalERC20')
        .withArgs(contractsOwner.address, erc20Token.address, amount);
    });
  });

  describe('transferExternalERC20()', () => {
    beforeEach(async () => {
      await prizePool.setPrizeStrategy(prizeStrategyManager.address);
    });

    it('should exit early when amount = 0', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc20Token.address).returns(true);

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .transferExternalERC20(contractsOwner.address, erc20Token.address, 0),
      ).to.not.emit(prizePool, 'TransferredExternalERC20');
    });

    it('should only allow the prizeStrategy to award external ERC20s', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc20Token.address).returns(true);

      let prizePool2 = prizePool.connect(wallet2 as Signer);

      await expect(
        prizePool2.transferExternalERC20(contractsOwner.address, wallet2.address, toWei('10')),
      ).to.be.revertedWith('PrizePool/only-prizeStrategy');
    });

    it('should allow arbitrary tokens to be transferred', async () => {
      const amount = toWei('10');

      await depositTokenIntoPrizePool(contractsOwner.address, amount, erc20Token);

      await yieldSourceStub.mock.canAwardExternal.withArgs(erc20Token.address).returns(true);

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .transferExternalERC20(contractsOwner.address, erc20Token.address, amount),
      )
        .to.emit(prizePool, 'TransferredExternalERC20')
        .withArgs(contractsOwner.address, erc20Token.address, amount);
    });
  });

  describe('awardExternalERC721()', () => {
    beforeEach(async () => {
      await prizePool.setPrizeStrategy(prizeStrategyManager.address);
    });

    it('should exit early when tokenIds list is empty', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc721Token.address).returns(true);

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .awardExternalERC721(contractsOwner.address, erc721Token.address, []),
      ).to.not.emit(prizePool, 'AwardedExternalERC721');
    });

    it('should only allow the prizeStrategy to award external ERC721s', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc721Token.address).returns(true);

      let prizePool2 = prizePool.connect(wallet2 as Signer);

      await expect(
        prizePool2.awardExternalERC721(contractsOwner.address, erc721Token.address, [NFT_TOKEN_ID]),
      ).to.be.revertedWith('PrizePool/only-prizeStrategy');
    });

    it('should allow arbitrary tokens to be transferred', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc721Token.address).returns(true);

      await depositNftIntoPrizePool(contractsOwner.address);

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .awardExternalERC721(contractsOwner.address, erc721Token.address, [NFT_TOKEN_ID]),
      )
        .to.emit(prizePool, 'AwardedExternalERC721')
        .withArgs(contractsOwner.address, erc721Token.address, [NFT_TOKEN_ID]);
    });

    it('should not DoS with faulty ERC721s', async () => {
      await yieldSourceStub.mock.canAwardExternal.withArgs(erc721tokenMock.address).returns(true);
      await erc721tokenMock.mock.transferFrom
        .withArgs(prizePool.address, contractsOwner.address, NFT_TOKEN_ID)
        .reverts();

      await expect(
        prizePool
          .connect(prizeStrategyManager)
          .awardExternalERC721(contractsOwner.address, erc721tokenMock.address, [NFT_TOKEN_ID]),
      ).to.emit(prizePool, 'ErrorAwardingExternalERC721');
    });
  });

  describe('onERC721Received()', () => {
    it('should receive an ERC721 token when using safeTransferFrom', async () => {
      expect(await erc721Token.balanceOf(prizePool.address)).to.equal('0');

      await depositNftIntoPrizePool(contractsOwner.address);

      expect(await erc721Token.balanceOf(prizePool.address)).to.equal('1');
    });
  });
});
