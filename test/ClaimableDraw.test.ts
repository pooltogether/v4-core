import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, constants, Contract, ContractFactory, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Address } from 'hardhat-deploy/dist/types';
import { Draw } from "./types"

const { getSigners } = ethers;
const { parseEther: toWei } = utils;
const { AddressZero } = constants

describe('ClaimableDraw', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let dai: Contract;
  let claimableDraw: Contract;
  let drawCalculator: MockContract;
  let drawHistory: MockContract;

  const DRAW_SAMPLE_CONFIG = {
    randomNumber: 11111,
    timestamp: 1111111111,
    prize: toWei('10'),
  };

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    let IDrawCalculator = await artifacts.readArtifact('IDrawCalculator');
    drawCalculator = await deployMockContract(wallet1, IDrawCalculator.abi);

    let IDrawHistory = await artifacts.readArtifact('IDrawHistory');
    drawHistory = await deployMockContract(wallet1, IDrawHistory.abi);

    const claimableDrawFactory: ContractFactory = await ethers.getContractFactory(
      'ClaimableDraw',
    );
    claimableDraw = await claimableDrawFactory.deploy(wallet1.address, drawHistory.address);

    const erc20MintableFactory: ContractFactory = await ethers.getContractFactory(
      'ERC20Mintable',
    );
    dai = await erc20MintableFactory.deploy('Dai Stablecoin', 'DAI');
  });

  /* =============================== */
  /* ======== Getter Tests ========= */
  /* =============================== */

  describe('Getter Functions', () => {
    describe('getDrawCalculator()', () => {
      it('should succeed to read an empty Draw ID => DrawCalculator mapping', async () => {
        expect(await claimableDraw.getDrawCalculator())
          .to.equal(drawCalculator.address);
      });
    })

    describe('getDrawHistory()', () => {
      it('should succesfully read global DrawHistory variable', async () => {
        expect(await claimableDraw.getDrawHistory())
          .to.equal(drawHistory.address)
      });
    });

    describe('getDrawPayoutBalanceOf()', () => {
      it('should return the user payout for draw before claiming a payout', async () => {
        expect(await claimableDraw.getDrawPayoutBalanceOf(wallet1.address, 0))
          .to.equal('0');
      });
    });
  })

  /* =============================== */
  /* ======== Setter Tests ========= */
  /* =============================== */
  describe('Setter Functions', () => {
    describe('setDrawHistory()', () => {
      it('should fail to set DrawHistory by unauthorized user', async () => {
        await expect(claimableDraw.connect(wallet3).setDrawHistory(ethers.Wallet.createRandom().address))
          .to.be.revertedWith('Ownable: caller is not the owner')
      });

      it('should fail to set DrawHistory with zero address', async () => {
        await expect(claimableDraw.setDrawHistory(AddressZero))
          .to.be.revertedWith('ClaimableDraw/draw-history-not-zero-address')
      });

      it('should succeed to set DrawHistory as owner', async () => {
        await expect(claimableDraw.setDrawHistory(wallet2.address))
          .to.emit(claimableDraw, 'DrawHistorySet')
          .withArgs(wallet2.address);
      });
    });

    describe('setDrawCalculator()', () => {
      it('should fail to set draw calculator from unauthorized wallet', async () => {
        const claimableDrawUnauthorized = claimableDraw.connect(wallet2);
        await expect(claimableDrawUnauthorized.setDrawCalculator(AddressZero))
          .to.be.revertedWith('Ownable: caller is not the owner');
      });

      it('should succeed to set new draw calculator for target draw id as owner', async () => {
        expect(await claimableDraw.setDrawCalculator(wallet2.address))
          .to.emit(claimableDraw, 'DrawCalculatorSet')
          .withArgs(wallet2.address);
      });

      it('should not allow a zero calculator', async () => {
        await expect(claimableDraw.setDrawCalculator(AddressZero))
          .to.be.revertedWith('ClaimableDraw/calc-not-zero')
      });

      it('should succeed to update draw calculator for target draw id as owner', async () => {
        await claimableDraw.setDrawCalculator(wallet2.address)
        expect(await claimableDraw.setDrawCalculator(wallet3.address))
          .to.emit(claimableDraw, 'DrawCalculatorSet')
          .withArgs(wallet3.address);
      });
    });
  })

  /* ====================================== */
  /* ======== Core External Tests ========= */
  /* ====================================== */
  describe('claim()', () => {
    it('should succeed to claim and emit ClaimedDraw event', async () => {
      const draw: any = { drawId: 1, winningRandomNumber: DRAW_SAMPLE_CONFIG.randomNumber, timestamp: DRAW_SAMPLE_CONFIG.timestamp }
      await drawHistory.mock.getDraws.withArgs([1]).returns([draw])
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])
      await expect(claimableDraw.claim(wallet1.address, [1], '0x'))
        .to.emit(claimableDraw, 'ClaimedDraw')
        .withArgs(wallet1.address, 1, toWei('10'));
    })

    it('should fail to claim a previously claimed prize', async () => {
      const draw: any = { drawId: 0, winningRandomNumber: DRAW_SAMPLE_CONFIG.randomNumber, timestamp: DRAW_SAMPLE_CONFIG.timestamp }
      await drawHistory.mock.getDraws.withArgs([0]).returns([draw])
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])

      // updated
      await claimableDraw.claim(wallet1.address, [0], '0x');

      // try again: should fail!
      await expect(claimableDraw.claim(wallet1.address, [0], '0x'))
        .to.be.revertedWith('ClaimableDraw/zero-payout');
    });

    it('should payout the difference if user claims more', async () => {
      const draw: any = { drawId: 1, winningRandomNumber: DRAW_SAMPLE_CONFIG.randomNumber, timestamp: DRAW_SAMPLE_CONFIG.timestamp }
      await drawHistory.mock.getDraws.withArgs([1]).returns([draw])

      // first time
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])
      await claimableDraw.claim(wallet1.address, [1], '0x');
      expect(await claimableDraw.getDrawPayoutBalanceOf(wallet1.address, 1)).to.equal(toWei('10'))

      // second time
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('20')])

      // try again; should reward diff
      await expect(claimableDraw.claim(wallet1.address, [1], '0x'))
        .to.emit(claimableDraw, 'ClaimedDraw')
        .withArgs(wallet1.address, 1, toWei('10'))
      expect(await claimableDraw.getDrawPayoutBalanceOf(wallet1.address, 1)).to.equal(toWei('20'))
    })
  });

  describe('withdrawERC20()', () => {
    let withdrawAmount: BigNumber = toWei('100');

    beforeEach(async () => {
      await dai.mint(claimableDraw.address, toWei('1000'));
    });

    it('should fail to withdraw ERC20 tokens as unauthorized account', async () => {
      expect(claimableDraw.connect(wallet3).withdrawERC20(dai.address, wallet1.address, withdrawAmount))
        .to.be.revertedWith('Ownable: caller is not the owner')
    });

    it('should fail to withdraw ERC20 tokens if recipient address is address zero', async () => {
      await expect(claimableDraw.withdrawERC20(dai.address, AddressZero, withdrawAmount))
        .to.be.revertedWith('ClaimableDraw/recipient-not-zero-address');
    });

    it('should fail to withdraw ERC20 tokens if token address is address zero', async () => {
      await expect(claimableDraw.withdrawERC20(AddressZero, wallet1.address, withdrawAmount))
        .to.be.revertedWith('ClaimableDraw/ERC20-not-zero-address');
    });

    it('should succeed to withdraw ERC20 tokens as owner', async () => {
      await expect(claimableDraw.withdrawERC20(dai.address, wallet1.address, withdrawAmount))
        .to.emit(claimableDraw, 'ERC20Withdrawn')
        .withArgs(dai.address, wallet1.address, withdrawAmount);
    });

  });
})
