import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, BigNumber } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { DrawSettings } from './types';

const { getSigners } = ethers;

export async function deployDrawCalculator(signer: any): Promise<Contract> {
  const drawCalculatorFactory = await ethers.getContractFactory(
  'TsunamiDrawCalculatorHarness',
  signer,
  );
  const drawCalculator: Contract = await drawCalculatorFactory.deploy();
  return drawCalculator;
}

describe('TsunamiDrawCalculator', () => {
    let drawCalculator: Contract; let ticket: MockContract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    const encoder = ethers.utils.defaultAbiCoder



  beforeEach(async () => {
    [wallet1, wallet2, wallet3] = await getSigners();
    drawCalculator = await deployDrawCalculator(wallet1);

    let ticketArtifact = await artifacts.readArtifact('Ticket');
    ticket = await deployMockContract(wallet1, ticketArtifact.abi);

    const drawSettings: DrawSettings = {
      distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
      pickCost: BigNumber.from(utils.parseEther('1')),
      matchCardinality: BigNumber.from(5),
      bitRangeSize: BigNumber.from(4),
    };
    
    await drawCalculator.initialize(ticket.address, drawSettings);
    
  });

  describe('admin functions', () => {
    it('onlyOwner can setPrizeSettings', async () => {
      const params: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
      };

      expect(await drawCalculator.setDrawSettings(params)).to.emit(
        drawCalculator,
        'DrawSettingsSet',
      );

      await expect(drawCalculator.connect(wallet2).setDrawSettings(params)).to.be.reverted;
    });

    it('cannot set over 100pc of prize for distribution', async () => {
      const params: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.9'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
      };
      await expect(drawCalculator.setDrawSettings(params)).to.be.revertedWith(
        'DrawCalc/distributions-gt-100%',
      );
    });
  });


  describe('calculateDistributionIndex()', () => {
    it('calculates distribution index 0', async () => {
      const drawSettings: DrawSettings = {
        matchCardinality: BigNumber.from(5),
        distributions: [
          ethers.utils.parseEther('0.6'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(4),
      };

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      const winningRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70"
      const userRandomNumber = "0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70"
      const prizeDistributionIndex: BigNumber= await drawCalculator.calculateDistributionIndex(userRandomNumber, winningRandomNumber, bitMasks)

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
      };
      // 252: 1111 1100
      // 255  1111 1111

      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks.length).to.eq(2) // same as length of matchCardinality
      expect(bitMasks[0]).to.eq(BigNumber.from(15))
      
      const prizeDistributionIndex: BigNumber= await drawCalculator.calculateDistributionIndex(252, 255, bitMasks)

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
        pickCost: BigNumber.from(utils.parseEther("1")),
        bitRangeSize: BigNumber.from(6),
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
      };
      const bitMasks = await drawCalculator.createBitMasks(drawSettings);
      expect(bitMasks[0]).to.eq(BigNumber.from(15)) // 1111
      expect(bitMasks[1]).to.eq(BigNumber.from(240)) // 11110000 
      
    })
  })

  describe('calculate()', () => {
    it('should calculate and win grand prize', async () => {
      const winningNumber = utils.solidityKeccak256(['address'], [wallet1.address]);
      const winningRandomNumber = utils.solidityKeccak256(
        ['bytes32', 'uint256'],
        [winningNumber, 1],
      );

      const timestamp = 42;
      const prizes = [utils.parseEther('100')];
      const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
      const ticketBalance = utils.parseEther('10');

      await ticket.mock.getBalancesAt.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]); // (user, timestamp): balance

      const prizesAwardable = await drawCalculator.calculate(
        wallet1.address,
        [winningRandomNumber],
        [timestamp],
        prizes,
        pickIndices,
      )

      expect(prizesAwardable[0]).to.equal(utils.parseEther('80'));

      console.log(
        'GasUsed for calculate(): ',
        (
          await drawCalculator.estimateGas.calculate(
            wallet1.address,
            [winningRandomNumber],
            [timestamp],
            prizes,
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

      const prizesAwardable = await drawCalculator.calculate(
        wallet1.address,
        [winningRandomNumber],
        [timestamp],
        prizes,
        pickIndices,
      )

      console.log(
        'GasUsed for calculate two picks(): ',
        (
          await drawCalculator.estimateGas.calculate(
            wallet1.address,
            [winningRandomNumber],
            [timestamp],
            prizes,
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
      const prizes = [utils.parseEther('100'), utils.parseEther('20')];
      const pickIndices = encoder.encode(['uint256[][]'], [[['1'], ['2']]]);
      const ticketBalance = utils.parseEther('10');
      const ticketBalance2 = utils.parseEther('10');

      await ticket.mock.getBalancesAt
        .withArgs(wallet1.address, [timestamp1, timestamp2])
        .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

      const prizesAwardable = await drawCalculator.calculate(
        wallet1.address,
        [winningRandomNumber, winningRandomNumber],
        [timestamp1, timestamp2],
        prizes,
        pickIndices,
      )

      expect(
        prizesAwardable[0]
      ).to.equal(utils.parseEther('80'));

      console.log(
        'GasUsed for 2 calculate() calls: ',
        (
          await drawCalculator.estimateGas.calculate(
            wallet1.address,
            [winningRandomNumber, winningRandomNumber],
            [timestamp1, timestamp2],
            prizes,
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
      const prizes = [utils.parseEther('100'), utils.parseEther('20')];
      const pickIndices = encoder.encode(['uint256[][]'], [[['1'], ['2']]]);
      const ticketBalance = utils.parseEther('10');
      const ticketBalance2 = utils.parseEther('0.4');

      await ticket.mock.getBalancesAt
        .withArgs(wallet1.address, [timestamp1, timestamp2])
        .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

      const drawSettings: DrawSettings = {
        distributions: [ethers.utils.parseEther('0.8'), ethers.utils.parseEther('0.2')],
        pickCost: BigNumber.from(utils.parseEther("10")),
        matchCardinality: BigNumber.from(5),
        bitRangeSize: BigNumber.from(4),
      };

      await drawCalculator.setDrawSettings(drawSettings)

      await expect(
        drawCalculator.calculate(
          wallet1.address,
          [winningRandomNumber, winningRandomNumber],
          [timestamp1, timestamp2],
          prizes,
          pickIndices,
        ),
      ).to.revertedWith('DrawCalc/insufficient-user-picks');
    });

    it('should calculate and win nothing', async () => {
      const winningNumber = utils.solidityKeccak256(['address'], [wallet2.address]);
      const userRandomNumber = utils.solidityKeccak256(['bytes32', 'uint256'], [winningNumber, 1]);
      const timestamp = 42;
      const prizes = [utils.parseEther('100')];
      const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
      const ticketBalance = utils.parseEther('10');

      await ticket.mock.getBalancesAt.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]); // (user, timestamp): balance

      const prizesAwardable = await drawCalculator.calculate(
        wallet1.address,
        [userRandomNumber],
        [timestamp],
        prizes,
        pickIndices,
      )

     expect(
        prizesAwardable[0]
      ).to.equal(utils.parseEther('0'));
    });

    it('increasing the matchCardinality for same user and winning numbers results in less of a prize', async () => {
      const timestamp = 42;
      const prizes = [utils.parseEther('100')];
      const pickIndices = encoder.encode(['uint256[][]'], [[['1']]]);
      const ticketBalance = utils.parseEther('10');

      await ticket.mock.getBalancesAt.withArgs(wallet1.address, [timestamp]).returns([ticketBalance]); // (user, timestamp): balance

      let params: DrawSettings = {
        matchCardinality: BigNumber.from(6),
        distributions: [
          ethers.utils.parseEther('0.2'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther('1')),
        bitRangeSize: BigNumber.from(4),
      };
      await drawCalculator.setDrawSettings(params);
 
      const resultingPrizes = await drawCalculator.calculate(
        wallet1.address,
        ["0x5d8cccf45ec07e30776960f9c3bf2d1f84008788bb1b90e5a2035e3bffea2b9f"],
        [timestamp],
        prizes,
        pickIndices,
      );
      expect(resultingPrizes[0]).to.equal(ethers.BigNumber.from(utils.parseEther('0.00244140625')));

      // now increase cardinality
      params = {
        matchCardinality: BigNumber.from(7),
        distributions: [
          ethers.utils.parseEther('0.2'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
          ethers.utils.parseEther('0.1'),
        ],
        pickCost: BigNumber.from(utils.parseEther('1')),
        bitRangeSize: BigNumber.from(4),
      };
      await drawCalculator.setDrawSettings(params);
      
      const resultingPrizes2 = await drawCalculator.calculate(
        wallet1.address,
        ["0x5be3732e3ee0b1d458a75c3e1b17afce42b255e81a588184bf91f01fdfed26f7"],
        [timestamp],
        prizes,
        pickIndices,
      );

      expect(resultingPrizes2[0]).to.equal(ethers.BigNumber.from("152587890625000"));
    });
  });
});
