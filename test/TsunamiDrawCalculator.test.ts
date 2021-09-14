import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Draw, DrawSettings } from './types';

const { getSigners } = ethers;

const newDebug = require('debug')

export async function deployDrawCalculator(signer: any): Promise<Contract> {
  const drawCalculatorFactory = await ethers.getContractFactory(
    'TsunamiDrawCalculatorHarness',
    signer,
  );
  const drawCalculator: Contract = await drawCalculatorFactory.deploy();
  return drawCalculator;
}

function calculateNumberOfWinnersAtIndex(bitRangeSize: number, distributionIndex: number): number {
  // Prize Count = (2**bitRange)**(cardinality-numberOfMatches)
  // if not grand prize: - (2^bitRange)**(cardinality-numberOfMatches-1)

  let prizeCount = ((2 ** bitRangeSize) ** (distributionIndex))
  if(distributionIndex > 0) {
    prizeCount -=  (2 ** bitRangeSize) ** (distributionIndex -1);
  }
  return prizeCount;
}

describe('TsunamiDrawCalculator', () => {
  let drawCalculator: Contract; let ticket: MockContract; let claimableDraw: MockContract;
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;

  const encoder = ethers.utils.defaultAbiCoder

  beforeEach(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
    drawCalculator = await deployDrawCalculator(wallet1);

    let ticketArtifact = await artifacts.readArtifact('ITicket');
    ticket = await deployMockContract(wallet1, ticketArtifact.abi);

    let claimableDrawArtifact = await artifacts.readArtifact('ClaimableDraw');
    claimableDraw = await deployMockContract(wallet1, claimableDrawArtifact.abi);

    await drawCalculator.initialize(ticket.address, wallet2.address, claimableDraw.address);
  });

  describe('initialize()', () => {
    let drawCalculator: Contract
    beforeEach(async () => {
      drawCalculator = await deployDrawCalculator(wallet1);
    })

    it('should require non-zero ticket', async () => {
      await expect(drawCalculator.initialize(ethers.constants.AddressZero, wallet2.address, claimableDraw.address)).to.be.revertedWith('DrawCalc/ticket-not-zero')
    })

    it('should require non-zero manager', async () => {
      await expect(drawCalculator.initialize(ticket.address, ethers.constants.AddressZero, claimableDraw.address)).to.be.revertedWith('Manager/manager-not-zero-address')
    })

    it('should require non-zero draw', async () => {
      await expect(drawCalculator.initialize(ticket.address, wallet2.address, ethers.constants.AddressZero)).to.be.revertedWith('DrawCalc/claimable-draw-not-zero-address')
    })
  })

  describe('setDrawSettings()', () => {
    it('should not allow anyone else to set', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      await expect(drawCalculator.connect(wallet3).setDrawSettings(0, drawSettings)).to.be.revertedWith('Manager/caller-not-manager-or-owner')
    })

    it('onlyOwner can setPrizeSettings', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };

      
      await claimableDraw.mock.setDrawCalculator.withArgs(0, drawCalculator.address).returns(drawCalculator.address);

      expect(await drawCalculator.setDrawSettings(0, drawSettings)).to.emit(
        drawCalculator,
        'DrawSettingsSet',
      );

      await expect(drawCalculator.connect(wallet2).setDrawSettings(drawSettings)).to.be.reverted;
    });

    it('cannot set over 100pc of prize for distribution', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      await expect(drawCalculator.setDrawSettings(0, drawSettings)).to.be.revertedWith(
        'DrawCalc/distributions-gt-100%',
      );
    });
    it('cannot set bitRangeSize = 0', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(0),
        prize: ethers.utils.parseEther('1'),
      };
      await expect(drawCalculator.setDrawSettings(0, drawSettings)).to.be.revertedWith(
        'DrawCalc/bitRangeSize-gt-0',
      );
    });
  });

  describe('setClaimableDraw()', () => {
    it('onlyOwnerOrManager can set', async () => {
      await expect(drawCalculator.setClaimableDraw(claimableDraw.address)).to.emit(
        drawCalculator,
        'ClaimableDrawSet',
      );
      await expect(drawCalculator.connect(wallet3).setClaimableDraw(claimableDraw.address)).to.be.reverted;
    })

    it('cant set to zero address', async () => {
      await expect(drawCalculator.setClaimableDraw(ethers.constants.AddressZero)).to.be.revertedWith("DrawCalc/claimable-draw-not-zero-address");
    })
  })

  describe('calculateDistributionIndex()', () => {
    it('grand prize gets the full fraction at index 0', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      const amount = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, BigNumber.from(0));
      expect(amount).to.equal(drawSettings.distributions[0]);
    })
    it('runner up gets part of the fraction at index 1', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      const amount = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, BigNumber.from(1));

      const prizeCount = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), 1)
      const expectedPrizeFraction = drawSettings.distributions[1].div(prizeCount)
      expect(amount).to.equal(expectedPrizeFraction);
    })
    it('all distribution indexes', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.5'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1')
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      for(let numberOfMatches = 0; numberOfMatches < drawSettings.distributions.length; numberOfMatches++) {
        
        const distributionIndex = BigNumber.from(drawSettings.distributions.length - numberOfMatches - 1) // minus one because we start at 0
        const fraction = await drawCalculator.calculatePrizeDistributionFraction(drawSettings, distributionIndex);

        let prizeCount = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), distributionIndex.toNumber())
        
        const expectedPrizeFraction = drawSettings.distributions[distributionIndex.toNumber()].div(prizeCount)
        expect(fraction).to.equal(expectedPrizeFraction);
      }
    })
  })

  describe('numberOfPrizesForIndex()', () => {
    it('calculates the number of prizes at distribution index 0', async () => {
      const bitRangeSize = 2
      const result = await drawCalculator.numberOfPrizesForIndex(bitRangeSize, BigNumber.from(0));
      expect(result).to.equal(1); // grand prize
    })

    it('calculates the number of prizes at distribution index 0', async () => {
      const bitRangeSize = 3
      const result = await drawCalculator.numberOfPrizesForIndex(bitRangeSize, BigNumber.from(4));
      // (2 ^ 3) ^  4 - (2 ^ 3) ^ (4-1) = 4096 - 512 = 3584
      expect(result).to.equal(3584)
    })

    it('calculates the number of prizes at all distribution indices', async () => {
      let drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.5'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1')
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      for(let distributionIndex = 0; distributionIndex < drawSettings.distributions.length; distributionIndex++) {
        const result = await drawCalculator.numberOfPrizesForIndex(drawSettings.bitRangeSize, distributionIndex);
        const expectedNumberOfWinners = calculateNumberOfWinnersAtIndex(drawSettings.bitRangeSize.toNumber(), distributionIndex)
        expect(result).to.equal(expectedNumberOfWinners);
      }
    })

  })

  describe('calculatePrizeDistributionFraction()', () => {
    it('calculates distribution index 0', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      const winningRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70"
      const userRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70" // intentionally same as winning random number
      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(userRandomNumber, winningRandomNumber, bitMasks)
      // all numbers match so grand prize!
      expect(prizeDistributionIndex).to.eq(BigNumber.from(0))
    })

    it('calculates distribution index 1', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      // 252: 1111 1100
      // 255  1111 1111

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks.length).to.eq(2) // same as length of matchCardinality
      expect(bitMasks[0]).to.eq(BigNumber.from(15))

      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(252, 255, bitMasks)

      // since the first 4 bits do not match the distribution index will be: (matchCardinality - numberOfMatches )= 2-0 = 2 
      expect(prizeDistributionIndex).to.eq(drawSettings.matchCardinality) 
    })

    it('calculates distribution index 1', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(3),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      // 527: 0010 0000 1111
      // 271  0001 0000 1111

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks.length).to.eq(3) // same as length of matchCardinality
      expect(bitMasks[0]).to.eq(BigNumber.from(15))

      const prizeDistributionIndex: BigNumber = await drawCalculator.calculateDistributionIndex(527, 271, bitMasks)

      // since the first 4 bits do not match the distribution index will be: (matchCardinality - numberOfMatches )= 3-2 = 1 
      expect(prizeDistributionIndex).to.eq(BigNumber.from(1)) 
    })

  })

  describe("createBitMasks()", () => {
    it("creates correct 6 bit masks", async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(6),
        prize: ethers.utils.parseEther('1'),
      };
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(63)) // 111111
      expect(bitMasks[1]).to.eq(BigNumber.from(4032)) // 11111100000

    })

    it("creates correct 4 bit masks", async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(2),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(15)) // 1111
      expect(bitMasks[1]).to.eq(BigNumber.from(240)) // 11110000 

    })
  })

  describe("getDrawSettings()", () => {
    it("gets correct draw settings", async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        numberOfPicks: BigNumber.from(utils.parseEther("10")),
        bitRangeSize: BigNumber.from(4),
        prize: ethers.utils.parseEther('1'),
      };
      
      await claimableDraw.mock.setDrawCalculator.withArgs(70, drawCalculator.address).returns(drawCalculator.address);
      await drawCalculator.setDrawSettings(70, drawSettings);
      
      const result = await drawCalculator.getDrawSettings(70);
      
      expect(result.matchCardinality).to.equal(drawSettings.matchCardinality)
      expect(result.bitRangeSize).to.equal(drawSettings.bitRangeSize)
      expect(result.prize).to.equal(drawSettings.prize)
      expect(result.numberOfPicks).to.equal(drawSettings.numberOfPicks)
      expect(result.distributions.length).to.equal(drawSettings.distributions.length)
      for(let i =0; i < result.distributions.length; i++) {
        expect(result.distributions[i]).to.deep.equal(drawSettings.distributions[i])
      }
    })
  })

  describe.only('calculate()', () => {
    const debug = newDebug('pt:TsunamiDrawCalculator.test.ts:calculate()')

    context('with draw 0 set', () => {
      let drawSettings: DrawSettings
      beforeEach(async () => {
        drawSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from(utils.parseEther('1')),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
        };
        await claimableDraw.mock.setDrawCalculator.withArgs(0, drawCalculator.address).returns(drawCalculator.address);
        await drawCalculator.setDrawSettings(0, drawSettings)
      })

      it('should calculate and win grand prize', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamp = 42;
        const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
        const ticketBalance = utils.parseEther('10');
        console.log("mocking getBalancesAt()")
        await ticket.mock.getBalancesAt.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]); // (user, timestamp): [balance]

        const draw: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp) }

        console.log("calculate()")
        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw],
          pickIndices,
        )

        expect(prizesAwardable[0]).to.equal(utils.parseEther('80'));

        debug(
          'GasUsed for calculate(): ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw],
              pickIndices,
            )
          ).toString(),
        );
      });

      it('should calculate and win grand prize multiple picks', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamp = 42;
        const prizes = [utils.parseEther('100')];
        const pickIndices = encoder.encode(['uint256[][]'], [[[...new Array<number>(1000).keys()]]]);
        const ticketBalance = utils.parseEther('20000');

        await ticket.mock.getBalancesAt.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]); // (user, timestamp): balance

        const draw: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp) }

        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw],
          pickIndices,
        )

        debug(
          'GasUsed for calculate 1000 picks(): ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw],
              pickIndices,
            )
          ).toString(),
        );
      });

      it('should calculate for multiple picks, first pick grand prize winner, second pick no winnings', async () => {
        //function calculate(address user, uint256[] calldata randomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external override view returns (uint256){

        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamp1 = 42;
        const timestamp2 = 51;
        
        const pickIndices = encoder.encode(['uint256[][]'], [[['1'], ['2']]]);
        const ticketBalance = utils.parseEther('10');
        const ticketBalance2 = utils.parseEther('10');


        const draw1: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp1) }
        const draw2: Draw = { drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp2) }

        await claimableDraw.mock.setDrawCalculator.withArgs(1, drawCalculator.address).returns(drawCalculator.address);

        await ticket.mock.getBalancesAt
          .withArgs(wallet1.address, [timestamp1, timestamp2])
          .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

        const drawSettings2: DrawSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from(utils.parseEther('1')),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('20'),
        };

        await drawCalculator.setDrawSettings(1, drawSettings2);


        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw1, draw2],
          pickIndices,
        )

        expect(
          prizesAwardable[0]
        ).to.equal(utils.parseEther('80'));

        debug(
          'GasUsed for 2 calculate() calls: ',
          (
            await drawCalculator.estimateGas.calculate(
              wallet1.address,
              [draw1, draw2],
              pickIndices,
            )
          ).toString(),
        );

      });

      it('should not have enough funds for a second pick and revert', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
        const winningRandomNumber = utils.solidityKeccak256(
          ['bytes32', 'uint256'],
          [winningNumber, 1],
        );

        const timestamp1 = 42;
        const timestamp2 = 51;
        const pickIndices = encoder.encode(['uint256[][]'], [[['1'], ['2']]]);
        const ticketBalance = utils.parseEther('10');
        const ticketBalance2 = utils.parseEther('0.4');

        await ticket.mock.getBalancesAt
          .withArgs(wallet1.address, [timestamp1, timestamp2])
          .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

        const drawSettings: DrawSettings = {
          distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
          numberOfPicks: BigNumber.from(utils.parseEther("10")),
          matchCardinality: BigNumber.from(5),
          bitRangeSize: BigNumber.from(4),
          prize: ethers.utils.parseEther('100'),
        };

        const draw1: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp1) }
        const draw2: Draw = { drawId: BigNumber.from(1), winningRandomNumber: BigNumber.from(winningRandomNumber), timestamp: BigNumber.from(timestamp2) }

        await claimableDraw.mock.setDrawCalculator.withArgs(1, drawCalculator.address).returns(drawCalculator.address);
        await drawCalculator.setDrawSettings(1, drawSettings)

        await expect(
          drawCalculator.calculate(
            wallet1.address,
            [draw1, draw2],
            pickIndices
          ),
        ).to.revertedWith('DrawCalc/insufficient-user-picks');
      });

      it('should calculate and win nothing', async () => {
        const winningNumber = utils.solidityKeccak256(['address'], [wallet2.address]);
        const userRandomNumber = utils.solidityKeccak256(['bytes32', 'uint256'], [winningNumber, 1]);
        const timestamp = 42;

        const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
        const ticketBalance = utils.parseEther('10');

        await ticket.mock.getBalancesAt.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]); // (user, timestamp): balance

        const draw1: Draw = { drawId: BigNumber.from(0), winningRandomNumber: BigNumber.from(userRandomNumber), timestamp: BigNumber.from(timestamp) }

        const prizesAwardable = await drawCalculator.calculate(
          wallet1.address,
          [draw1],
          pickIndices,
        )

        expect(
          prizesAwardable[0]
        ).to.equal(utils.parseEther('0'));
      });
    })
  });
});
