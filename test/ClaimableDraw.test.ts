import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, constants, Contract, ContractFactory, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Address } from 'hardhat-deploy/dist/types';
import { Draw } from "./types"

const { getSigners } = ethers;
const { parseEther: toWei } = utils;

async function userClaimWithMock(
  drawCalculator: MockContract,
  drawSettings: any,
  claimableDraw: Contract,
  user: Address,
  drawIds: Array<any>,
  drawCalculators: Array<any>,
) {
  await drawCalculator.mock.calculate
    .withArgs(
      user,
      [drawSettings.randomNumber],
      [drawSettings.timestamp],
      [drawSettings.prize],
      '0x',
    )
    .returns([drawSettings.payout]);

  return await claimableDraw.claim(user, drawIds, drawCalculators, ['0x']);
}

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
      'ClaimableDrawHarness',
    );
    claimableDraw = await claimableDrawFactory.deploy();

    await claimableDraw.initialize(wallet1.address, drawHistory.address);

    const erc20MintableFactory: ContractFactory = await ethers.getContractFactory(
      'ERC20Mintable',
    );
    dai = await erc20MintableFactory.deploy('Dai Stablecoin', 'DAI');
  });

  describe('wrapCardinality()', () => {
    it('should convert a draw id to a draw index before reaching cardinality', async () => {
      const wrapCardinality = await claimableDraw.wrapCardinality(1);
      expect(wrapCardinality)
        .to.equal(1)
    });

    it('should convert a draw id to a draw index after reaching cardinality', async () => {
      const wrapCardinality = await claimableDraw.wrapCardinality(13);
      expect(wrapCardinality)
        .to.equal(5)
    });
  });

  describe('calculateDrawCollectionPayout()', () => {
    it('should return a total payout after calculating a draw collection prize', async () => {
      const draw: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(DRAW_SAMPLE_CONFIG.randomNumber), timestamp: BigNumber.from(DRAW_SAMPLE_CONFIG.timestamp) }

      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])
      await drawHistory.mock.getDraws.withArgs([0]).returns([draw])

      const calculateDrawCollectionPayoutResult = await claimableDraw.callStatic.calculateDrawCollectionPayout(
        wallet1.address, // _user
        [
          BigNumber.from('0'),
          BigNumber.from('0'),
          BigNumber.from('0'),
          BigNumber.from('0'),
          BigNumber.from('0'),
          BigNumber.from('0'),
          BigNumber.from('0'),
          BigNumber.from('0')
        ], // _userClaimedDraws
        [0], // _drawIds
        drawCalculator.address, // _drawCalculator
        '0x' // _data
      );

      expect(calculateDrawCollectionPayoutResult.totalPayout)
        .to.equal(toWei('10'))
    });
  });

  describe('_updateUserDrawPayout()', () => {
    it('should an update draw claim payout history with the full payout amount in index 0', async () => {
      const payoutHistory = [BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0')]
      const updatedPayoutHistory = await claimableDraw.updateUserDrawPayout(payoutHistory, 0, toWei('10'))
      expect(updatedPayoutHistory[1][0])
        .to.equal(toWei('10'))
    });

    it('should an update draw claim payout history with the diff payout amount in index 0', async () => {
      const payoutHistory = [toWei('5'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0')]
      const updatedPayoutHistory = await claimableDraw.updateUserDrawPayout(payoutHistory, 0, toWei('10'))
      expect(updatedPayoutHistory[1][0])
        .to.equal(toWei('5'))
    });
    it('should an update draw claim payout history with the full payout amount in index 7', async () => {
      const payoutHistory = [BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0')]
      const updatedPayoutHistory = await claimableDraw.updateUserDrawPayout(payoutHistory, 7, toWei('10'))
      expect(updatedPayoutHistory[1][7])
        .to.equal(toWei('10'))
    });

    it('should an update draw claim payout history with the diff payout amount in index 7', async () => {
      const payoutHistory = [BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), BigNumber.from('0'), toWei('5')]
      const updatedPayoutHistory = await claimableDraw.updateUserDrawPayout(payoutHistory, 7, toWei('10'))
      expect(updatedPayoutHistory[1][7])
        .to.equal(toWei('5'))
    });
  });

  describe('userDrawClaim()', () => {
    it('should return the user payout for draw before claiming a payout', async () => {
      expect(await claimableDraw.userDrawClaim(wallet1.address, 0))
        .to.equal('0');
    });

    it('should return the user payout for draw after claiming a payout', async () => {
      await claimableDraw.setUserDrawPayoutHistory(wallet1.address, [toWei('1'), toWei('2'), toWei('3'), toWei('4'), toWei('5'), toWei('6'), toWei('7'), toWei('8')]);
      expect(await claimableDraw.userDrawClaim(wallet1.address, 0))
        .to.equal(toWei('1'));

      expect(await claimableDraw.userDrawClaim(wallet1.address, 7))
        .to.equal(toWei('8'));
    });
  });

  describe('userDrawClaims()', () => {
    it('should read an uninitialized userClaimedDraws', async () => {
      const userClaimedDraws = await claimableDraw.userDrawClaims(wallet1.address);
      expect(userClaimedDraws[0])
        .to.equal('0')
    });
  });

  describe('setManager()', () => {
    it('should fail to set draw manager from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = claimableDraw.connect(wallet2);
      await expect(claimableDrawUnauthorized.setManager(wallet2.address)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should fail to set draw manager with zero address', async () => {
      await expect(claimableDraw.setManager(constants.AddressZero)).to.be.reverted
    });

    it('should fail to set draw manager with existing draw manager', async () => {
      await expect(claimableDraw.setManager(wallet1.address)).to.be.reverted
    });

    it('should succeed to set new draw manager', async () => {
      await expect(claimableDraw.setManager(wallet2.address))
        .to.emit(claimableDraw, 'ManagerTransferred')
        .withArgs(wallet2.address);
    });
  });

  describe('setDrawHistory()', () => {

    it('only owner or manager should be able to set', async () => {
      await expect(claimableDraw.connect(wallet3).setDrawHistory(ethers.Wallet.createRandom().address)).to.be.reverted
    });

    it('should fail to set draw history with zero address', async () => {
      await expect(claimableDraw.setDrawHistory(constants.AddressZero)).to.be.reverted
    });

    it('owner or manager should succeed to set new draw manager', async () => {
      await expect(claimableDraw.setDrawHistory(wallet2.address))
        .to.emit(claimableDraw, 'DrawHistorySet')
        .withArgs(wallet2.address);

      await claimableDraw.setManager(wallet2.address)
      await expect(claimableDraw.connect(wallet2).setDrawHistory(wallet2.address))
        .to.emit(claimableDraw, 'DrawHistorySet')
        .withArgs(wallet2.address);
    });
  });

  describe('setDrawCalculator()', () => {
    it('should fail to set draw calculator from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = claimableDraw.connect(wallet2);
      expect(claimableDrawUnauthorized.setDrawCalculator(0, constants.AddressZero))
        .to.be.revertedWith('Manager/caller-not-manager-or-owner');
    });

    it('should fail to set draw calculator with zero address as manager', async () => {
      await claimableDraw.setManager(wallet2.address)
      await expect(claimableDraw.connect(wallet2).setDrawCalculator(0, constants.AddressZero))
        .to.be.revertedWith('ClaimableDraw/calculator-not-zero-address');
    });

    it('should succeed to set draw calculator with zero address as owner', async () => {
      await expect(claimableDraw.setDrawCalculator(0, constants.AddressZero))
        .to.emit(claimableDraw, 'DrawCalculatorSet')
        .withArgs(0, constants.AddressZero);
    });

    it('should succeed to set new draw calculator for target draw id as manager', async () => {
      await claimableDraw.setManager(wallet2.address)
      await expect(claimableDraw.connect(wallet2).setDrawCalculator(0, wallet2.address))
        .to.emit(claimableDraw, 'DrawCalculatorSet')
        .withArgs(0, wallet2.address);
    });

    it('should succeed to set new draw calculator for target draw id as owner', async () => {
      expect(claimableDraw.setDrawCalculator(0, wallet2.address))
        .to.emit(claimableDraw, 'DrawCalculatorSet')
        .withArgs(0, wallet2.address);
    });

    it('should fail to update draw calculator for target draw id as manager', async () => {
      await claimableDraw.setManager(wallet2.address)
      await claimableDraw.setDrawCalculator(0, wallet2.address)
      expect(claimableDraw.connect(wallet2).setDrawCalculator(0, wallet3.address))
        .to.be.revertedWith('ClaimableDraw/draw-calculator-previous-set')
    });

    it('should succeed to update draw calculator for target draw id as owner', async () => {
      await claimableDraw.setDrawCalculator(0, wallet2.address)
      expect(claimableDraw.setDrawCalculator(0, wallet3.address))
        .to.emit(claimableDraw, 'DrawCalculatorSet')
        .withArgs(0, wallet3.address);
    });
  });

  describe('claim()', () => {
    // function claim(address _user, uint32[][] calldata _drawIds, IDrawCalculator[] calldata _drawCalculators, bytes[] calldata _data) external returns (uint256) {
    it('should fail to claim with incorrect amount of draw calculators', async () => {
      const draw: any = { drawId: 0, winningRandomNumber: DRAW_SAMPLE_CONFIG.randomNumber, timestamp: DRAW_SAMPLE_CONFIG.timestamp }


      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])
      await drawHistory.mock.getDraws.withArgs([0]).returns([draw])

      await expect(
        claimableDraw.claim(
          wallet1.address,
          [[0]],
          [drawCalculator.address, drawCalculator.address],
          ['0x'],
        ),
      ).to.be.revertedWith('ClaimableDraw/invalid-calculator-array');
    });

    it('should fail to claim a previously claimed prize', async () => {
      const draw: any = { drawId: 0, winningRandomNumber: DRAW_SAMPLE_CONFIG.randomNumber, timestamp: DRAW_SAMPLE_CONFIG.timestamp }

      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])
      await drawHistory.mock.getDraws.withArgs([0]).returns([draw])

      await claimableDraw.claim(wallet1.address, [[0]], [drawCalculator.address], ['0x']);

      await expect(claimableDraw.claim(wallet1.address, [[0]], [drawCalculator.address], ['0x']))
        .to.be.revertedWith('ClaimableDraw/payout-below-threshold');
    });

    it('should succeed to claim and emit ClaimedDraw event', async () => {

      const draw: any = { drawId: 0, winningRandomNumber: DRAW_SAMPLE_CONFIG.randomNumber, timestamp: DRAW_SAMPLE_CONFIG.timestamp }

      await drawCalculator.mock.calculate.withArgs(wallet1.address, [draw], '0x').returns([toWei('10')])
      await drawHistory.mock.getDraws.withArgs([0]).returns([draw])

      await expect(claimableDraw.claim(wallet1.address, [[0]], [drawCalculator.address], ['0x']))
        .to.emit(claimableDraw, 'ClaimedDraw')
        .withArgs(
          wallet1.address,
          toWei('10'),
        );

      const userClaimedDraws = await claimableDraw.userDrawClaims(wallet1.address);
      expect(userClaimedDraws[0])
        .to.equal(toWei('10'))
    })

    it('should create 8 draws and a user claims all draw ids in a single claim', async () => {

      let drawsIds = [];
      let drawRandomNumbers = [];
      let drawTimestamps = [];
      let drawPrizes = [];
      let draws: Draw[] = []

      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 8;

      // prepare claim data
      for (let index = 0; index < CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp,
          prize: DRAW_SAMPLE_CONFIG.prize,
          payout: toWei('' + index),
        };


        drawsIds.push(BigNumber.from(index));
        drawRandomNumbers.push(MOCK_UNIQUE_DRAW.randomNumber);
        drawTimestamps.push(MOCK_UNIQUE_DRAW.timestamp);
        drawPrizes.push(MOCK_UNIQUE_DRAW.prize);

        draws.push({
          drawId: BigNumber.from(index),
          winningRandomNumber: BigNumber.from(MOCK_UNIQUE_DRAW.randomNumber),
          timestamp: BigNumber.from(MOCK_UNIQUE_DRAW.timestamp),
        })
      }

      await drawHistory.mock.getDraws.withArgs(drawsIds).returns(draws)
      const payouts = [toWei('1'), toWei('2'), toWei('3'), toWei('4'), toWei('5'), toWei('6'), toWei('7'), toWei('8')]

      await drawCalculator.mock.calculate.withArgs(wallet1.address, draws, '0x').returns(payouts)
      await claimableDraw.claim(wallet1.address, [drawsIds], [drawCalculator.address], ['0x']);

      const payoutHistory = await claimableDraw.userDrawClaims(wallet1.address)

      for (let index = 0; index < payoutHistory.length; index++) {
        expect(payoutHistory[index]).to.equal(payouts[index]);
      }

      // TODO: Fix a deep equal to remove extra expect statements
      // expect(await claimableDraw.userDrawClaims(wallet1.address)).to.equal(payoutExpectation); // FAILS
    });
  });

  describe('withdrawERC20()', () => {
    let withdrawAmount: BigNumber;

    beforeEach(async () => {
      withdrawAmount = toWei('100');

      await dai.mint(claimableDraw.address, toWei('1000'));
    });

    it('should withdraw ERC20 tokens', async () => {
      await claimableDraw.setManager(wallet2.address);

      expect(
        await claimableDraw
          .connect(wallet2)
          .withdrawERC20(dai.address, wallet1.address, withdrawAmount),
      )
        .to.emit(claimableDraw, 'ERC20Withdrawn')
        .withArgs(dai.address, wallet1.address, withdrawAmount);
    });

    it('should fail to withdraw ERC20 tokens if not owner or assetManager', async () => {
      await expect(
        claimableDraw.connect(wallet2).withdrawERC20(dai.address, wallet1.address, withdrawAmount),
      ).to.be.revertedWith('Manager/caller-not-manager-or-owner');
    });

    it('should fail to withdraw ERC20 tokens if token address is address zero', async () => {
      await claimableDraw.setManager(wallet2.address);

      await expect(
        claimableDraw
          .connect(wallet2)
          .withdrawERC20(constants.AddressZero, wallet1.address, withdrawAmount),
      ).to.be.revertedWith('ClaimableDraw/ERC20-not-zero-address');
    });
  });
});
