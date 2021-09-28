import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, constants, Contract, ContractFactory, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';

const { getSigners } = ethers;
const { parseEther: toWei } = utils;
const { AddressZero } = constants

describe('DrawPrize', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let dai: Contract;
  let ticket: Contract;
  let drawPrize: Contract;
  let drawCalculator: MockContract;

  before(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
  });

  beforeEach(async () => {
    const erc20MintableFactory: ContractFactory = await ethers.getContractFactory(
      'ERC20Mintable',
    );
    dai = await erc20MintableFactory.deploy('Dai Stablecoin', 'DAI');
    ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');

    let IDrawCalculator = await artifacts.readArtifact('IDrawCalculator');
    drawCalculator = await deployMockContract(wallet1, IDrawCalculator.abi);

    const drawPrizeFactory: ContractFactory = await ethers.getContractFactory(
      'DrawPrize',
    );
    drawPrize = await drawPrizeFactory.deploy(wallet1.address, ticket.address, drawCalculator.address);

    await ticket.mint(drawPrize.address, toWei('1000'));
  });

  /* =============================== */
  /* ======== Getter Tests ========= */
  /* =============================== */

  describe('Getter Functions', () => {
    describe('getDrawCalculator()', () => {
      it('should succeed to read an empty Draw ID => DrawCalculator mapping', async () => {
        expect(await drawPrize.getDrawCalculator())
          .to.equal(drawCalculator.address);
      });
    })

    describe('getDrawPayoutBalanceOf()', () => {
      it('should return the user payout for draw before claiming a payout', async () => {
        expect(await drawPrize.getDrawPayoutBalanceOf(wallet1.address, 0))
          .to.equal('0');
      });
    });

    describe('getToken()', () => {
      it('should succesfully read global token variable', async () => {
        expect(await drawPrize.getToken())
          .to.equal(ticket.address)
      });
    });
  })

  /* =============================== */
  /* ======== Setter Tests ========= */
  /* =============================== */
  describe('Setter Functions', () => {
    describe('setDrawCalculator()', () => {
      it('should fail to set draw calculator from unauthorized wallet', async () => {
        const drawPrizeUnauthorized = drawPrize.connect(wallet2);
        await expect(drawPrizeUnauthorized.setDrawCalculator(AddressZero))
          .to.be.revertedWith('Ownable/caller-not-owner');
      });

      it('should succeed to set new draw calculator for target draw id as owner', async () => {
        expect(await drawPrize.setDrawCalculator(wallet2.address))
          .to.emit(drawPrize, 'DrawCalculatorSet')
          .withArgs(wallet2.address);
      });

      it('should not allow a zero calculator', async () => {
        await expect(drawPrize.setDrawCalculator(AddressZero))
          .to.be.revertedWith('DrawPrize/calc-not-zero')
      });

      it('should succeed to update draw calculator for target draw id as owner', async () => {
        await drawPrize.setDrawCalculator(wallet2.address)
        expect(await drawPrize.setDrawCalculator(wallet3.address))
          .to.emit(drawPrize, 'DrawCalculatorSet')
          .withArgs(wallet3.address);
      });
    });
  })

  /* ====================================== */
  /* ======== Core External Tests ========= */
  /* ====================================== */
  describe('claim()', () => {
    it('should succeed to claim and emit ClaimedDraw event', async () => {
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [1], '0x').returns([toWei('10')])
      await expect(drawPrize.claim(wallet1.address, [1], '0x'))
        .to.emit(drawPrize, 'ClaimedDraw')
        .withArgs(wallet1.address, 1, toWei('10'));
    })

    it('should fail to claim a previously claimed prize', async () => {
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [0], '0x').returns([toWei('10')])

      // updated
      await drawPrize.claim(wallet1.address, [0], '0x');

      // try again: should fail!
      await expect(drawPrize.claim(wallet1.address, [0], '0x'))
        .to.be.revertedWith('DrawPrize/zero-payout');
    });

    it('should payout the difference if user claims more', async () => {
      // first time
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [1], '0x').returns([toWei('10')])
      await drawPrize.claim(wallet1.address, [1], '0x');
      expect(await drawPrize.getDrawPayoutBalanceOf(wallet1.address, 1)).to.equal(toWei('10'))

      // second time
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [1], '0x').returns([toWei('20')])

      // try again; should reward diff
      await expect(drawPrize.claim(wallet1.address, [1], '0x'))
        .to.emit(drawPrize, 'ClaimedDraw')
        .withArgs(wallet1.address, 1, toWei('10'))
      expect(await drawPrize.getDrawPayoutBalanceOf(wallet1.address, 1)).to.equal(toWei('20'))
    })
  });

  describe('withdrawERC20()', () => {
    let withdrawAmount: BigNumber = toWei('100');

    beforeEach(async () => {
      await dai.mint(drawPrize.address, toWei('1000'));
    });

    it('should fail to withdraw ERC20 tokens as unauthorized account', async () => {
      expect(drawPrize.connect(wallet3).withdrawERC20(dai.address, wallet1.address, withdrawAmount))
        .to.be.revertedWith('Ownable/caller-not-owner')
    });

    it('should fail to withdraw ERC20 tokens if recipient address is address zero', async () => {
      await expect(drawPrize.withdrawERC20(dai.address, AddressZero, withdrawAmount))
        .to.be.revertedWith('DrawPrize/recipient-not-zero-address');
    });

    it('should fail to withdraw ERC20 tokens if token address is address zero', async () => {
      await expect(drawPrize.withdrawERC20(AddressZero, wallet1.address, withdrawAmount))
        .to.be.revertedWith('DrawPrize/ERC20-not-zero-address');
    });

    it('should succeed to withdraw ERC20 tokens as owner', async () => {
      await expect(drawPrize.withdrawERC20(dai.address, wallet1.address, withdrawAmount))
        .to.emit(drawPrize, 'ERC20Withdrawn')
        .withArgs(dai.address, wallet1.address, withdrawAmount);
    });

  });
})
