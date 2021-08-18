import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, constants, Contract, ContractFactory } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Address } from 'hardhat-deploy/dist/types';

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
    .returns(drawSettings.payout);

  return await claimableDraw.claim(user, drawIds, drawCalculators, ['0x']);
}

describe('ClaimableDraw', () => {
  let wallet1: any;
  let wallet2: any;
  let claimableDraw: Contract;
  let drawCalculator: MockContract;

  const DRAW_SAMPLE_CONFIG = {
    randomNumber: 1,
    timestamp: 11,
    prize: 10,
  };

  const DRAW_SECOND_CONFIG = {
    randomNumber: 22222,
    timestamp: 2222222222,
    prize: toWei('10000'),
  };

  before(async () => {
    [wallet1, wallet2] = await getSigners();
  });

  beforeEach(async () => {
    let IDrawCalculator = await artifacts.readArtifact('IDrawCalculator');
    drawCalculator = await deployMockContract(wallet1, IDrawCalculator.abi);

    const claimableDrawFactory: ContractFactory = await ethers.getContractFactory(
      'ClaimableDrawHarness',
    );
    claimableDraw = await claimableDrawFactory.deploy();

    await claimableDraw.initialize(wallet1.address, drawCalculator.address); // Sets initial draw manager
    await claimableDraw.createDraw(
      DRAW_SAMPLE_CONFIG.randomNumber,
      DRAW_SAMPLE_CONFIG.timestamp,
      DRAW_SAMPLE_CONFIG.prize,
    );
  });

  describe('createDraw()', () => {
    it('should fail to create a new draw when called from non-draw-manager', async () => {
      const claimableDrawWallet2 = claimableDraw.connect(wallet2);
      await expect(
        claimableDrawWallet2.createDraw(
          DRAW_SECOND_CONFIG.randomNumber,
          DRAW_SECOND_CONFIG.timestamp,
          DRAW_SECOND_CONFIG.prize,
        ),
      ).to.be.revertedWith('ClaimableDraw/unauthorized-draw-manager');
    });

    it('should create a new draw and emit an event', async () => {
      await expect(
        await claimableDraw.createDraw(
          DRAW_SECOND_CONFIG.randomNumber,
          DRAW_SECOND_CONFIG.timestamp,
          DRAW_SECOND_CONFIG.prize,
        ),
      )
        .to.emit(claimableDraw, 'DrawSet')
        .withArgs(
          1,
          DRAW_SECOND_CONFIG.randomNumber,
          DRAW_SECOND_CONFIG.timestamp,
          DRAW_SECOND_CONFIG.prize,
          drawCalculator.address,
        );
    });
  });

  describe('userClaimedDraws()', () => {
    it('should read an uninitialized userClaimedDraws', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address);
      console.log(userClaimedDraws)
    });
  });

  describe('getDraw()', () => {
    it('should fail to read non-existent draw', async () => {
      await expect(claimableDraw.getDraw(1)).to.revertedWith('ClaimableDraw/draw-nonexistent');
    });

    it('should read the recently created draw struct which includes the current calculator', async () => {
      // await claimableDraw.createDraw(DRAW_SAMPLE_CONFIG.randomNumber, DRAW_SAMPLE_CONFIG.timestamp, DRAW_SAMPLE_CONFIG.prize)
      const draw = await claimableDraw.getDraw(0);
      expect(draw.randomNumber).to.equal(DRAW_SAMPLE_CONFIG.randomNumber);
      expect(draw.prize).to.equal(DRAW_SAMPLE_CONFIG.prize);
      expect(draw.timestamp).to.equal(DRAW_SAMPLE_CONFIG.timestamp);
      expect(draw.calculator).to.equal(drawCalculator.address);
    });
  });

  describe('setDrawManager()', () => {
    it('should fail to set draw manager from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = await claimableDraw.connect(wallet2);
      await expect(claimableDrawUnauthorized.setDrawManager(wallet2.address)).to.be.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('should fail to set draw manager with zero address', async () => {
      await expect(claimableDraw.setDrawManager(constants.AddressZero)).to.be.revertedWith(
        'ClaimableDraw/draw-manager-not-zero-address',
      );
    });

    it('should fail to set draw manager with existing draw manager', async () => {
      await expect(claimableDraw.setDrawManager(wallet1.address)).to.be.revertedWith(
        'ClaimableDraw/existing-draw-manager-address',
      );
    });

    it('should succeed to set new draw manager', async () => {
      await expect(claimableDraw.setDrawManager(wallet2.address))
        .to.emit(claimableDraw, 'DrawManagerSet')
        .withArgs(wallet2.address);
    });
  });

  describe('setDrawCalculator()', () => {
    it('should fail to set draw calculator from unauthorized wallet', async () => {
      const claimableDrawUnauthorized = claimableDraw.connect(wallet2);
      await expect(
        claimableDrawUnauthorized.setDrawCalculator(constants.AddressZero),
      ).to.be.revertedWith('Ownable: caller is not the owner');
    });

    it('should fail to set draw calculator with zero address', async () => {
      await expect(claimableDraw.setDrawCalculator(constants.AddressZero)).to.be.revertedWith(
        'ClaimableDraw/calculator-not-zero-address',
      );
    });

    it('should fail to set draw calculator with existing draw calculator', async () => {
      await expect(claimableDraw.setDrawCalculator(constants.AddressZero)).to.be.revertedWith(
        'ClaimableDraw/calculator-not-zero-address',
      );
    });

    it('should succeed to set new draw calculator', async () => {
      await expect(claimableDraw.setDrawCalculator(wallet2.address))
        .to.emit(claimableDraw, 'DrawCalculatorSet')
        .withArgs(wallet2.address);
    });
  });

  describe('hasClaimed()', () => {
    it('should fail to claim a previously claimed prize', async () => {
      const MOCK_DRAW = { ...DRAW_SAMPLE_CONFIG, payout: toWei('100') };
      await userClaimWithMock(
        drawCalculator,
        MOCK_DRAW,
        claimableDraw,
        wallet1.address,
        [[0]],
        [drawCalculator.address],
      );

      await expect(
        userClaimWithMock(
          drawCalculator,
          MOCK_DRAW,
          claimableDraw,
          wallet1.address,
          [[0]],
          [drawCalculator.address],
        ),
      ).to.be.revertedWith('ClaimableDraw/user-previously-claimed');
    });

    it('should claim a prize and check claimed status', async () => {
      const MOCK_DRAW = { ...DRAW_SAMPLE_CONFIG, payout: toWei('100') };
      await userClaimWithMock(
        drawCalculator,
        MOCK_DRAW,
        claimableDraw,
        wallet1.address,
        [[0]],
        [drawCalculator.address],
      );

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000001',
      );

      expect(await claimableDraw.hasClaimed(wallet1.address, 0)).to.equal(true);
    });
  });

  describe('claim()', () => {
    beforeEach(async () => {
      const claimableDrawFactory: ContractFactory = await ethers.getContractFactory(
        'ClaimableDrawHarness',
      );
      claimableDraw = await claimableDrawFactory.deploy();
      await claimableDraw.initialize(wallet1.address, drawCalculator.address); // Sets initial draw manager
    });

    it('should fail to claim with incorrect amount of draw calculators', async () => {
      await claimableDraw.createDraw(
        DRAW_SAMPLE_CONFIG.randomNumber,
        DRAW_SAMPLE_CONFIG.timestamp,
        DRAW_SAMPLE_CONFIG.prize,
      );
      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));
      await expect(
        claimableDraw.claim(
          wallet1.address,
          [[0]],
          [drawCalculator.address, drawCalculator.address],
          ['0x'],
        ),
      ).to.be.revertedWith('ClaimableDraw/invalid-calculator-array');
    });

    it('should fail to claim with invalid draw calculator', async () => {
      await claimableDraw.createDraw(
        DRAW_SAMPLE_CONFIG.randomNumber,
        DRAW_SAMPLE_CONFIG.timestamp,
        DRAW_SAMPLE_CONFIG.prize,
      );
      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));
      await expect(
        claimableDraw.claim(wallet1.address, [[0]], [constants.AddressZero], ['0x']),
      ).to.be.revertedWith('ClaimableDraw/calculator-address-invalid');
    });

    it.only('should succeed to claim and emit ', async () => {
      const MOCK_DRAW = { ...DRAW_SAMPLE_CONFIG, payout: toWei('100') };
      await claimableDraw.createDraw(
        DRAW_SAMPLE_CONFIG.randomNumber,
        DRAW_SAMPLE_CONFIG.timestamp,
        DRAW_SAMPLE_CONFIG.prize,
      );
      await expect(
        await userClaimWithMock(
          drawCalculator,
          MOCK_DRAW,
          claimableDraw,
          wallet1.address,
          [[0]],
          [drawCalculator.address],
        ),
      )
        .to.emit(claimableDraw, 'ClaimedDraw')
        .withArgs(
          wallet1.address,
          MOCK_DRAW.payout,
        );

      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address);
      expect(userClaimedDraws[0])
        .to.equal(toWei('100'))

    })


    it('should fail to claim a previously claimed prize', async () => {
      let drawsIds: Array<Array<number>> = [[], []];
      let drawRandomNumbers: Array<Array<number>> = [[], []];
      let drawTimestamps: Array<Array<number>> = [[], []];
      let drawPrizes: Array<Array<number>> = [[], []];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 2;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index < CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
          payout: toWei('' + index),
        };

        if (index == 0) {
          drawsIds[0].push(index);
          drawRandomNumbers[0].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[0].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[0].push(MOCK_UNIQUE_DRAW.prize);
        }

        if (index > 0) {
          drawsIds[1].push(index);
          drawRandomNumbers[1].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[1].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[1].push(MOCK_UNIQUE_DRAW.prize);
        }

        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );
      }

      // First User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[0], drawTimestamps[0], drawPrizes[0], '0x')
        .returns(toWei('500'));
      await claimableDraw.claim(wallet1.address, [drawsIds[0]], [drawCalculator.address], ['0x']);

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000001',
      );

      // Second User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[0], drawTimestamps[0], drawPrizes[0], '0x')
        .returns(toWei('500'));

      await expect(
        claimableDraw.claim(wallet1.address, [drawsIds[0]], [drawCalculator.address], ['0x']),
      ).to.be.revertedWith('ClaimableDraw/user-previously-claimed');
    });

    it('should create 20 draws and fail when a user claims draw id 10 twice', async () => {
      let drawsIds: Array<Array<number>> = [[], []];
      let drawRandomNumbers: Array<Array<number>> = [[], []];
      let drawTimestamps: Array<Array<number>> = [[], []];
      let drawPrizes: Array<Array<number>> = [[], []];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 36;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index <= CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
          payout: toWei('' + index),
        };

        if (index == 10 || index == 12) {
          drawsIds[0].push(index);
          drawRandomNumbers[0].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[0].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[0].push(MOCK_UNIQUE_DRAW.prize);
        }

        if (index == 10) {
          drawsIds[1].push(index);
          drawRandomNumbers[1].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[1].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[1].push(MOCK_UNIQUE_DRAW.prize);
        }

        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );
      }

      // First User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[0], drawTimestamps[0], drawPrizes[0], '0x')
        .returns(toWei('500'));
      await claimableDraw.claim(wallet1.address, [drawsIds[0]], [drawCalculator.address], ['0x']);
      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000001400',
      );

      // Second User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[1], drawTimestamps[1], drawPrizes[1], '0x')
        .returns(toWei('500'));

      await expect(
        claimableDraw.claim(wallet1.address, [drawsIds[1]], [drawCalculator.address], ['0x']),
      ).to.be.revertedWith('ClaimableDraw/user-previously-claimed');
    });

    it('should create 37 draws and a user claims all draw ids in a single claim', async () => {
      let drawsIds = [];
      let drawRandomNumbers = [];
      let drawTimestamps = [];
      let drawPrizes = [];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 36;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index <= CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
          payout: toWei('' + index),
        };

        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );
        drawsIds.push(index);
        drawRandomNumbers.push(MOCK_UNIQUE_DRAW.randomNumber);
        drawTimestamps.push(MOCK_UNIQUE_DRAW.timestamp);
        drawPrizes.push(MOCK_UNIQUE_DRAW.prize);
      }

      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers, drawTimestamps, drawPrizes, '0x')
        .returns(toWei('500'));

      await claimableDraw.claim(wallet1.address, [drawsIds], [drawCalculator.address], ['0x']);

      await expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000001fffffffff',
      );

      expect(await claimableDraw.hasClaimed(wallet1.address, 36)).to.equal(true);
    });

    it('should create 37 draws and a user claims on 3,4,7,8 draw ids in a single claim', async () => {
      let drawsIds = [];
      let drawRandomNumbers = [];
      let drawTimestamps = [];
      let drawPrizes = [];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 36;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index <= CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
          payout: toWei('' + index),
        };
        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );

        if (index == 3 || index == 4 || index == 7 || index == 8) {
          drawsIds.push(index);
          drawRandomNumbers.push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps.push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes.push(MOCK_UNIQUE_DRAW.prize);
        }
      }
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers, drawTimestamps, drawPrizes, '0x')
        .returns(toWei('500'));

      await claimableDraw.claim(wallet1.address, [drawsIds], [drawCalculator.address], ['0x']);

      await expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000198',
      );

      expect(await claimableDraw.hasClaimed(wallet1.address, 36)).to.equal(false);
    });

    it('should create 37 draws and split user claims between 3,4 and 7,8 draw ids ', async () => {
      let drawsIds: Array<Array<number>> = [[], []];
      let drawRandomNumbers: Array<Array<number>> = [[], []];
      let drawTimestamps: Array<Array<number>> = [[], []];
      let drawPrizes: Array<Array<number>> = [[], []];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 36;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index <= CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
        };
        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );

        if (index == 3 || index == 4) {
          drawsIds[0].push(index);
          drawRandomNumbers[0].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[0].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[0].push(MOCK_UNIQUE_DRAW.prize);
        }

        if (index == 18 || index == 19) {
          drawsIds[1].push(index);
          drawRandomNumbers[1].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[1].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[1].push(MOCK_UNIQUE_DRAW.prize);
        }
      }

      // First User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[0], drawTimestamps[0], drawPrizes[0], '0x')
        .returns(toWei('500'));

      await claimableDraw.claim(wallet1.address, [drawsIds[0]], [drawCalculator.address], ['0x']);

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000018',
      );

      // Second User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[1], drawTimestamps[1], drawPrizes[1], '0x')
        .returns(toWei('500'));

      await claimableDraw.claim(wallet1.address, [drawsIds[1]], [drawCalculator.address], ['0x']);

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x00000000000000000000000000000000000000000000000000000000000c0018',
      );
    });

    it('should create a 257 draws and user should claim all non-expired draw ids', async () => {
      let drawsIdsSplit: Array<Array<number>> = [[], []];
      let drawRandomNumbers: Array<Array<number>> = [[], []];
      let drawTimestamps: Array<Array<number>> = [[], []];
      let drawPrizes: Array<Array<number>> = [[], []];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 257;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index < CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
          payout: toWei('' + index),
        };

        if (index <= 0) {
          drawsIdsSplit[0].push(index);
          drawRandomNumbers[0].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[0].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[0].push(MOCK_UNIQUE_DRAW.prize);
        }

        if (index >= 1) {
          drawsIdsSplit[1].push(index);
          drawRandomNumbers[1].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[1].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[1].push(MOCK_UNIQUE_DRAW.prize);
        }

        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );
      }

      await expect(
        claimableDraw.claim(wallet1.address, [drawsIdsSplit[0]], [drawCalculator.address], ['0x']),
      ).to.be.revertedWith('ClaimableDraw/claim-expired');

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000000',
      );

      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[1], drawTimestamps[1], drawPrizes[1], '0x')
        .returns(toWei('500'));

      await claimableDraw.claim(
        wallet1.address,
        [drawsIdsSplit[1]],
        [drawCalculator.address],
        ['0x'],
      );

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      );

      expect(await claimableDraw.hasClaimed(wallet1.address, 7)).to.equal(true);

      expect(await claimableDraw.hasClaimed(wallet1.address, 256)).to.equal(true);
    });

    it('should create a 320 draws and user should claim all non-expired draw ids in 3 separate transactions', async () => {
      let drawsIdsSplit: Array<Array<number>> = [[], [], []];
      let drawRandomNumbers: Array<Array<number>> = [[], [], []];
      let drawTimestamps: Array<Array<number>> = [[], [], []];
      let drawPrizes: Array<Array<number>> = [[], [], []];
      let MOCK_UNIQUE_DRAW;
      const CLAIM_COUNT = 320;

      await drawCalculator.mock.calculate
        .withArgs(
          wallet1.address,
          [DRAW_SAMPLE_CONFIG.randomNumber],
          [DRAW_SAMPLE_CONFIG.timestamp],
          [DRAW_SAMPLE_CONFIG.prize],
          '0x',
        )
        .returns(toWei('100'));

      for (let index = 0; index <= CLAIM_COUNT; index++) {
        MOCK_UNIQUE_DRAW = {
          randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
          timestamp: DRAW_SAMPLE_CONFIG.timestamp * index,
          prize: DRAW_SAMPLE_CONFIG.prize * index,
          payout: toWei('' + index),
        };

        if (index <= 64) {
          drawsIdsSplit[0].push(index);
          drawRandomNumbers[0].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[0].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[0].push(MOCK_UNIQUE_DRAW.prize);
        }

        if (index >= 65 && index <= 256) {
          drawsIdsSplit[1].push(index);
          drawRandomNumbers[1].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[1].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[1].push(MOCK_UNIQUE_DRAW.prize);
        }

        if (index >= 257 && index < 320) {
          drawsIdsSplit[2].push(index);
          drawRandomNumbers[2].push(MOCK_UNIQUE_DRAW.randomNumber);
          drawTimestamps[2].push(MOCK_UNIQUE_DRAW.timestamp);
          drawPrizes[2].push(MOCK_UNIQUE_DRAW.prize);
        }

        await claimableDraw.createNewDraw(
          MOCK_UNIQUE_DRAW.randomNumber,
          MOCK_UNIQUE_DRAW.timestamp,
          MOCK_UNIQUE_DRAW.prize,
        );
      }

      // First User Claim
      await expect(
        claimableDraw.claim(wallet1.address, [drawsIdsSplit[0]], [drawCalculator.address], ['0x']),
      ).to.be.revertedWith('ClaimableDraw/claim-expired');

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000000',
      );

      // Seconder User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[1], drawTimestamps[1], drawPrizes[1], '0x')
        .returns(toWei('500'));
      await claimableDraw.claim(
        wallet1.address,
        [drawsIdsSplit[1]],
        [drawCalculator.address],
        ['0x'],
      );

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0xfffffffffffffffffffffffffffffffffffffffffffffffe0000000000000001',
      );

      // Validate first batch of user draw claims
      for (let index = 0; index < drawsIdsSplit[0].length; index++) {
        let element = drawsIdsSplit[0][index];
        await expect(claimableDraw.hasClaimed(wallet1.address, element)).to.be.revertedWith(
          'ClaimableDraw/claim-expired',
        );
      }

      // Validate second batch of user draw claims
      for (let index = 0; index < drawsIdsSplit[1].length; index++) {
        let element = drawsIdsSplit[1][index];
        expect(await claimableDraw.hasClaimed(wallet1.address, element)).to.equal(true);
      }

      expect(await claimableDraw.hasClaimed(wallet1.address, 256)).to.equal(true);

      // Third User Claim
      await drawCalculator.mock.calculate
        .withArgs(wallet1.address, drawRandomNumbers[2], drawTimestamps[2], drawPrizes[2], '0x')
        .returns(toWei('500'));

      await claimableDraw.claim(
        wallet1.address,
        [drawsIdsSplit[2]],
        [drawCalculator.address],
        ['0x'],
      );

      // Validate third batch of user draw claims
      for (let index = 0; index < drawsIdsSplit[2].length; index++) {
        let element = drawsIdsSplit[1][index];
        expect(await claimableDraw.hasClaimed(wallet1.address, element)).to.equal(true);
      }

      expect(await claimableDraw.userClaimedDraws(wallet1.address)).to.equal(
        '0xfffffffffffffffffffffffffffffffffffffffffffffffeffffffffffffffff',
      );
    });
  });

  describe('test internal bitwise operations', () => {
    it('check the first user draw claim was correctly set', async () => {
      const MOCK_DRAW = { ...DRAW_SAMPLE_CONFIG, payout: toWei('100') };
      const userClaimedDrawsBefore = await claimableDraw.userClaimedDraws(wallet1.address);
      const readLastClaimFromClaimedHistoryBeforeClaim = await claimableDraw.readLastClaimFromClaimedHistory(
        userClaimedDrawsBefore,
        0,
      );
      await userClaimWithMock(
        drawCalculator,
        MOCK_DRAW,
        claimableDraw,
        wallet1.address,
        [[0]],
        [drawCalculator.address],
      );

      const userClaimedDrawsAfter = await claimableDraw.userClaimedDraws(wallet1.address);
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.readLastClaimFromClaimedHistory(
        userClaimedDrawsAfter,
        0,
      );

      expect(readLastClaimFromClaimedHistoryBeforeClaim).to.equal(false);
      expect(readLastClaimFromClaimedHistoryAfterClaim).to.equal(true);
    });

    it('check the 1st user draw claim was correctly set', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address);
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.writeLastClaimFromClaimedHistory(
        userClaimedDraws,
        0,
      );
      expect(readLastClaimFromClaimedHistoryAfterClaim).to.equal(
        '0x0000000000000000000000000000000000000000000000000000000000000001',
      );
    });

    it('check the 37th user draw claim was correctly set', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address);
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.writeLastClaimFromClaimedHistory(
        userClaimedDraws,
        36,
      );
      expect(readLastClaimFromClaimedHistoryAfterClaim).to.equal(
        '0x0000000000000000000000000000000000000000000000000000001000000000',
      );
    });

    it('check the 100th user draw claim was correctly set', async () => {
      const userClaimedDraws = await claimableDraw.userClaimedDraws(wallet1.address);
      const readLastClaimFromClaimedHistoryAfterClaim = await claimableDraw.writeLastClaimFromClaimedHistory(
        userClaimedDraws,
        99,
      );
      expect(readLastClaimFromClaimedHistoryAfterClaim).to.equal(
        '0x0000000000000000000000000000000000000008000000000000000000000000',
      );
    });
  });
});
