import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { BigNumber, constants, Contract, utils } from 'ethers';
import { ethers, artifacts } from 'hardhat';

import { call } from '../helpers/call';

const { AddressZero } = constants;
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
  let multiTokenPrizePool: any;

  let yieldSourceStub: MockContract;

  let reserve: MockContract;
  let reserveRegistry: MockContract;

  let depositToken: Contract;
  let erc20Token: Contract;
  let erc721Token: Contract;
  let erc721tokenMock: MockContract;

  let ticket: Contract;
  let sponsorship: MockContract;

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
      await pool.depositTo(walletAddress, amount, ticket.address);
    } else {
      await token.transfer(pool.address, amount);
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

    const IERC721 = await artifacts.readArtifact('IERC721Upgradeable');
    erc721tokenMock = await deployMockContract(contractsOwner as Signer, IERC721.abi);

    const YieldSourceStub = await artifacts.readArtifact('YieldSourceStub');
    yieldSourceStub = await deployMockContract(contractsOwner as Signer, YieldSourceStub.abi);
    await yieldSourceStub.mock.depositToken.returns(depositToken.address);

    const ReserveInterface = await artifacts.readArtifact('ReserveInterface');
    reserve = await deployMockContract(contractsOwner as Signer, ReserveInterface.abi);

    const RegistryInterface = await artifacts.readArtifact('RegistryInterface');
    reserveRegistry = await deployMockContract(contractsOwner as Signer, RegistryInterface.abi);
    await reserveRegistry.mock.lookup.returns(reserve.address);

    debug('deploying PrizePoolHarness...');

    const PrizePoolHarness = await getContractFactory('PrizePoolHarness', contractsOwner);
    prizePool = await PrizePoolHarness.deploy();

    const Ticket = await getContractFactory('Ticket');
    ticket = await Ticket.deploy();
    await ticket.initialize('name', 'SYMBOL', 18, prizePool.address);
  });

  describe('initialize()', () => {
    it('should fire the events', async () => {
      let tx = prizePool.initializeAll(reserve.address, [ticket.address], yieldSourceStub.address);

      await expect(tx).to.emit(prizePool, 'ControlledTokenAdded').withArgs(ticket.address);

      await expect(prizePool.setPrizeStrategy(prizeStrategyManager.address))
        .to.emit(prizePool, 'PrizeStrategySet')
        .withArgs(prizeStrategyManager.address);
    });
  });

  describe('with a mocked prize pool', () => {
    beforeEach(async () => {
      await prizePool.initializeAll(
        reserveRegistry.address,
        [ticket.address],
        yieldSourceStub.address,
      );

      await prizePool.setPrizeStrategy(prizeStrategyManager.address);
    });

    describe('initialize()', () => {
      it('should set all the vars', async () => {
        expect(await prizePool.token()).to.equal(depositToken.address);
        expect(await prizePool.reserveRegistry()).to.equal(reserveRegistry.address);
      });

      it('should reject invalid params', async () => {
        const _initArgs = [reserveRegistry.address, [ticket.address], yieldSourceStub.address];

        let initArgs;

        debug('deploying secondary prizePool...');
        const PrizePoolHarness = await getContractFactory('PrizePoolHarness', contractsOwner);
        prizePool2 = await PrizePoolHarness.deploy();

        debug('testing initialization of secondary prizeStrategy...');

        initArgs = _initArgs.slice();
        initArgs[0] = AddressZero;
        await expect(prizePool2.initializeAll(...initArgs)).to.be.revertedWith(
          'PrizePool/reserveRegistry-not-zero',
        );

        initArgs = _initArgs.slice();
        initArgs[1] = [AddressZero];
        await expect(prizePool2.initializeAll(...initArgs)).to.be.revertedWith(
          'PrizePool/controlledToken-not-zero-address',
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
          prizePool.depositTo(wallet2.address, amount, ticket.address),
        ).to.be.revertedWith('PrizePool/exceeds-liquidity-cap');
      });
    });

    describe('captureAwardBalance()', () => {
      it('should handle when the balance is less than the collateral', async () => {
        await depositTokenIntoPrizePool(contractsOwner.address, toWei('100'));

        await yieldSourceStub.mock.balanceOfToken
          .withArgs(prizePool.address)
          .returns(toWei('99.9999'));

        await expect(prizePool.captureAwardBalance()).to.not.emit(prizePool, 'ReserveFeeCaptured');
        expect(await prizePool.awardBalance()).to.equal(toWei('0'));
      });

      it('should handle the situ when the total accrued interest is less than the captured total', async () => {
        await depositTokenIntoPrizePool(contractsOwner.address, toWei('100'));

        await yieldSourceStub.mock.balanceOfToken.withArgs(prizePool.address).returns(toWei('110'));
        await reserve.mock.reserveRateMantissa.returns('0');

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
        await reserve.mock.reserveRateMantissa.returns('0');

        await expect(prizePool.captureAwardBalance()).to.not.emit(prizePool, 'ReserveFeeCaptured');
        expect(await prizePool.awardBalance()).to.equal(toWei('10'));
      });

      it('should capture the reserve fees', async () => {
        const reserveFee = toWei('1');

        await depositTokenIntoPrizePool(contractsOwner.address, toWei('1000'));

        await reserve.mock.reserveRateMantissa.returns(toWei('0.01'));

        await yieldSourceStub.mock.balanceOfToken
          .withArgs(prizePool.address)
          .returns(toWei('1100'));

        let tx = prizePool.captureAwardBalance();

        await expect(tx).to.emit(prizePool, 'ReserveFeeCaptured').withArgs(reserveFee);

        await expect(tx).to.emit(prizePool, 'AwardCaptured').withArgs(toWei('99'));

        expect(await prizePool.awardBalance()).to.equal(toWei('99'));
        expect(await prizePool.reserveTotalSupply()).to.equal(reserveFee);
      });
    });

    describe('calculateReserveFee()', () => {
      it('should return zero when no reserve fee is set', async () => {
        await reserve.mock.reserveRateMantissa.returns(toWei('0'));
        expect(await prizePool.calculateReserveFee(toWei('1'))).to.equal(toWei('0'));
      });

      it('should calculate an accurate reserve fee on a given amount', async () => {
        await reserve.mock.reserveRateMantissa.returns(toWei('0.5'));
        expect(await prizePool.calculateReserveFee(toWei('1'))).to.equal(toWei('0.5'));
      });
    });

    describe('withdrawReserve()', () => {
      it('should allow the reserve to be withdrawn', async () => {
        await depositTokenIntoPrizePool(contractsOwner.address, toWei('1000'));

        await reserve.mock.reserveRateMantissa.returns(toWei('0.01'));
        await yieldSourceStub.mock.balanceOfToken
          .withArgs(prizePool.address)
          .returns(toWei('1100'));

        // capture the reserve of 1 token
        await prizePool.captureAwardBalance();

        await yieldSourceStub.mock.redeemToken.withArgs(toWei('1')).returns(toWei('0.8'));

        await reserve.call(prizePool, 'withdrawReserve', contractsOwner.address);

        expect(await prizePool.reserveTotalSupply()).to.equal('0');
      });
    });

    describe('withdrawInstantlyFrom()', () => {
      it('should allow a user to withdraw instantly', async () => {
        let amount = toWei('10');

        await depositTokenIntoPrizePool(contractsOwner.address, amount);

        await yieldSourceStub.mock.redeemToken.withArgs(amount).returns(amount);

        await expect(
          prizePool.withdrawInstantlyFrom(contractsOwner.address, amount, ticket.address),
        )
          .to.emit(prizePool, 'InstantWithdrawal')
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

    describe('tokens()', () => {
      it('should return all tokens', async () => {
        expect(await prizePool.tokens()).to.deep.equal([ticket.address]);
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
        ).to.be.revertedWith('Ownable: caller is not the owner');
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
          'Ownable: caller is not the owner',
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
        ).to.be.revertedWith('Ownable: caller is not the owner');
      });

      it('should not delegate if the balance is zero', async () => {
        await compLike.mock.balanceOf.withArgs(prizePool.address).returns('0');
        await prizePool.compLikeDelegate(compLike.address, wallet2.address);
      });
    });
  });

  describe('with a multi-token prize pool', () => {
    beforeEach(async () => {
      debug('deploying PrizePoolHarness...');
      const PrizePoolHarness = await getContractFactory('PrizePoolHarness', contractsOwner);
      multiTokenPrizePool = await PrizePoolHarness.deploy();

      const Ticket = await getContractFactory('Ticket');

      ticket = await Ticket.deploy();
      await ticket.initialize('name', 'SYMBOL', 18, multiTokenPrizePool.address);

      const ControlledToken = await artifacts.readArtifact('ControlledToken');
      sponsorship = await deployMockContract(contractsOwner as Signer, ControlledToken.abi);

      await sponsorship.mock.controller.returns(multiTokenPrizePool.address);

      await multiTokenPrizePool.initializeAll(
        reserveRegistry.address,
        [ticket.address, sponsorship.address],
        yieldSourceStub.address,
      );

      await multiTokenPrizePool.setPrizeStrategy(prizeStrategyManager.address);
    });

    describe('accountedBalance()', () => {
      it('should return the total accounted balance for all tokens', async () => {
        await sponsorship.mock.totalSupply.returns(toWei('456'));

        await depositTokenIntoPrizePool(
          contractsOwner.address,
          toWei('123'),
          depositToken,
          multiTokenPrizePool,
        );

        expect(await multiTokenPrizePool.accountedBalance()).to.equal(toWei('579'));
      });

      it('should include the reserve', async () => {
        await sponsorship.mock.totalSupply.returns(toWei('50'));
        await yieldSourceStub.mock.balanceOfToken
          .withArgs(multiTokenPrizePool.address)
          .returns(toWei('110'));
        await reserve.mock.reserveRateMantissa.returns(toWei('0.1'));

        await depositTokenIntoPrizePool(
          contractsOwner.address,
          toWei('50'),
          depositToken,
          multiTokenPrizePool,
        );

        // first capture the 10 tokens as 9 prize and 1 reserve
        await multiTokenPrizePool.captureAwardBalance();

        await yieldSourceStub.mock.balanceOfToken
          .withArgs(multiTokenPrizePool.address)
          .returns(toWei('110'));

        // now try to capture again
        expect(await multiTokenPrizePool.accountedBalance()).to.equal(toWei('101'));
      });
    });
  });

  describe('awardExternalERC20()', () => {
    beforeEach(async () => {
      await prizePool.initializeAll(
        prizeStrategyManager.address,
        [ticket.address],
        yieldSourceStub.address,
      );
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
      await prizePool.initializeAll(
        prizeStrategyManager.address,
        [ticket.address],
        yieldSourceStub.address,
      );
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
      await prizePool.initializeAll(
        prizeStrategyManager.address,
        [ticket.address],
        yieldSourceStub.address,
      );
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
