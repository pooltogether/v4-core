import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, constants } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Address } from 'node:cluster';

const { getSigners } = ethers;
const { parseEther: toWei } = utils;

async function userClaimWithMock(drawCalculator:MockContract, drawSettings: any, claimableDraw:Contract, user: Address, drawIds: Array<any>, drawCalculators: Array<any>) {
  await drawCalculator.mock.calculate
    .withArgs(user, [drawSettings.randomNumber], [drawSettings.timestamp], [drawSettings.prize], '0x')
    .returns(drawSettings.payout)
  
  return await claimableDraw.claim(user, drawIds, drawCalculators, '0x')
}

describe('ClaimableDraw', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let claimableDraw: Contract;
  let drawCalculator: MockContract;

  let DRAW_FIRST_CONFIG = {
    randomNumber: 11111,
    timestamp: 1111111111,
    prize: 10000,
  }

  before(async () =>{
    [ wallet1, wallet2, wallet3 ] = await getSigners();
  })
  
  beforeEach(async () =>{
    let IDrawCalculator = await artifacts.readArtifact('IDrawCalculator')
    drawCalculator = await deployMockContract(wallet1, IDrawCalculator.abi)

    const claimableDrawFactory: ContractFactory = await ethers.getContractFactory("ClaimableDrawHarness");
    claimableDraw = await claimableDrawFactory.deploy();

    await claimableDraw.initialize(wallet1.address) // Sets initial draw manager
    await claimableDraw.setDrawCalculator(drawCalculator.address)
    await claimableDraw.createDraw(DRAW_FIRST_CONFIG.randomNumber, DRAW_FIRST_CONFIG.timestamp, DRAW_FIRST_CONFIG.prize)
  })

  describe('createDraw()', () => {
    it('should fail to create a new draw when called from non-draw-manager', async () => {
      const DRAW_SECOND_CONFIG = {
        randomNumber: 22222,
        timestamp: 2222222222,
        prize: toWei('10000'),
      }
      const claimableDrawWallet2 = claimableDraw.connect(wallet2)
      await expect(claimableDrawWallet2.createDraw(DRAW_SECOND_CONFIG.randomNumber, DRAW_SECOND_CONFIG.timestamp, DRAW_SECOND_CONFIG.prize))
        .to.be.revertedWith('ClaimableDraw/unauthorized-draw-manager')
    })
    
    it('should create a new draw', async () => {
      const DRAW_SECOND_CONFIG = {
        randomNumber: 22222,
        timestamp: 2222222222,
        prize: toWei('10000'),
      }

      await expect(await claimableDraw.createDraw(DRAW_SECOND_CONFIG.randomNumber, DRAW_SECOND_CONFIG.timestamp, DRAW_SECOND_CONFIG.prize))
        .to.emit(claimableDraw, 'DrawSet')
        .withArgs(DRAW_SECOND_CONFIG.randomNumber, DRAW_SECOND_CONFIG.timestamp, DRAW_SECOND_CONFIG.prize, drawCalculator.address)
    })
  });
  
  describe('setDrawManager()', () => {
    it('should fail to set draw manager from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = await claimableDraw.connect(wallet2)
      await expect(claimableDrawUnauthorized.setDrawManager(wallet2.address))
        .to.be.revertedWith('Ownable: caller is not the owner')
    })

    it('should fail to set draw manager with zero address', async () => {
      await expect(claimableDraw.setDrawManager(constants.AddressZero))
        .to.be.revertedWith('ClaimableDraw/draw-manager-not-zero-address')
    })
    
    it('should fail to set draw manager with existing draw manager', async () => {
      await expect(claimableDraw.setDrawManager(wallet1.address))
        .to.be.revertedWith('ClaimableDraw/existing-draw-manager-address')
    })
    
    it('should succeed to set new draw manager', async () => {
      await expect(claimableDraw.setDrawManager(wallet2.address))
        .to.emit(claimableDraw, 'DrawManagerSet')
        .withArgs(wallet2.address)
    })
  })

  describe('setDrawCalculator()', () => {
    it('should fail to set draw calculator from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = claimableDraw.connect(wallet2)
      await expect(claimableDrawUnauthorized.setDrawCalculator(constants.AddressZero))
        .to.be.revertedWith('Ownable: caller is not the owner')
    })
  
    it('should fail to set draw calculator with zero address', async () => {
      await expect(claimableDraw.setDrawCalculator(constants.AddressZero))
        .to.be.revertedWith('ClaimableDraw/calculator-not-zero-address')
    })
    
    it('should fail to set draw calculator with existing draw calculator', async () => {
      await expect(claimableDraw.setDrawCalculator(constants.AddressZero))
        .to.be.revertedWith('ClaimableDraw/calculator-not-zero-address')
    })
    
    it('should succeed to set new draw calculator', async () => {
      await expect(claimableDraw.setDrawCalculator(wallet2.address))
        .to.emit(claimableDraw, 'DrawCalculatorSet')
        .withArgs(wallet2.address)
    })
  })

  describe('claim()', () => {
    it('should fail to claim with invalid draw calculator', async () => {
      const MOCK_DRAW = {...DRAW_FIRST_CONFIG, payout: toWei("100")}
      await expect(userClaimWithMock(drawCalculator, MOCK_DRAW, claimableDraw, wallet1.address, [[0]], [constants.AddressZero]))
        .to.be.revertedWith('ClaimableDraw/calculator-address-invalid')
    })
    
    it('should fail to claim with incorrect amount of draw calculators', async () => {
      const MOCK_DRAW = {...DRAW_FIRST_CONFIG, payout: toWei("100")}
      await expect(userClaimWithMock(drawCalculator, MOCK_DRAW, claimableDraw, wallet1.address, [[0]], [drawCalculator.address, drawCalculator.address]))
        .to.be.revertedWith('ClaimableDraw/invalid-calculator-array')
    })

    it('should claim', async () => {
      const MOCK_DRAW = {...DRAW_FIRST_CONFIG, payout: toWei("100")}
      await expect(await userClaimWithMock(drawCalculator, MOCK_DRAW, claimableDraw, wallet1.address, [[0]], [drawCalculator.address]))
        .to.emit(claimableDraw, 'Claimed')
        .withArgs(wallet1.address, '0x0000000000000000000000000000000000000000000000000000000000000001', toWei("100"))
    })
  });
  
  describe('hasClaimed()', () => {
    it('should claim a prize and check claimed status', async () => {
      const MOCK_DRAW = {...DRAW_FIRST_CONFIG, payout: toWei("100")}
      await userClaimWithMock(drawCalculator, MOCK_DRAW, claimableDraw, wallet1.address, [[0]], [drawCalculator.address])

      await expect(await claimableDraw.userClaimedDraws(wallet1.address))
        .to.equal('0x0000000000000000000000000000000000000000000000000000000000000001');

      expect(await claimableDraw.hasClaimed(wallet1.address, 0))
        .to.equal(true)
    })
  });

  describe('test internal bitwise operations', () => {
    
    it('check the first user draw claim was correctly set', async () => {
      const MOCK_DRAW = {...DRAW_FIRST_CONFIG, payout: toWei("100")}
      const userClaimedDrawsBefore = await claimableDraw.userClaimedDraws(wallet1.address)
      const readLastClaimFromClaimedHistoryBeforeClaim = await claimableDraw.readLastClaimFromClaimedHistory(userClaimedDrawsBefore, 0)
      await userClaimWithMock(drawCalculator, MOCK_DRAW, claimableDraw, wallet1.address, [[0]], [drawCalculator.address])

      const userClaimedDrawsAfter = await claimableDraw.userClaimedDraws(wallet1.address)
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.readLastClaimFromClaimedHistory(userClaimedDrawsAfter, 0)

      expect(readLastClaimFromClaimedHistoryBeforeClaim)
        .to.equal(false);
      expect(readLastClaimFromClaimedHistoryAfterClaim)
        .to.equal(true);
    })
    
    it('check the 1st user draw claim was correctly set', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address)
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.writeLastClaimFromClaimedHistory(userClaimedDraws, 0)
      expect(readLastClaimFromClaimedHistoryAfterClaim)
        .to.equal('0x0000000000000000000000000000000000000000000000000000000000000001');
    })

    it('check the 37th user draw claim was correctly set', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address)
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.writeLastClaimFromClaimedHistory(userClaimedDraws, 36)
      expect(readLastClaimFromClaimedHistoryAfterClaim)
        .to.equal('0x0000000000000000000000000000000000000000000000000000001000000000');
    })
    
    it('check the 100th user draw claim was correctly set', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address)
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.writeLastClaimFromClaimedHistory(userClaimedDraws, 99)
      expect(readLastClaimFromClaimedHistoryAfterClaim)
        .to.equal('0x0000000000000000000000000000000000000008000000000000000000000000');
    })
  })
})
