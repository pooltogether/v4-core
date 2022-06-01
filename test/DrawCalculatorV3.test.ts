import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { BigNumber, Contract } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Draw, PrizeConfig } from './types';
import { fillPrizeTiersWithZeros } from './helpers/fillPrizeTiersWithZeros';

const { constants, getSigners, provider, utils } = ethers;
const { AddressZero } = constants;
const { parseEther: toWei, parseUnits } = utils;

const newDebug = require('debug');

function newDraw(overrides: any): Draw {
    return {
        drawId: 1,
        timestamp: 0,
        winningRandomNumber: 2,
        beaconPeriodStartedAt: 0,
        beaconPeriodSeconds: 1,
        ...overrides,
    };
}

function assertEmptyArrayOfBigNumbers(array: BigNumber[]) {
    array.forEach((element: BigNumber) => {
        expect(element).to.equal(BigNumber.from(0));
    });
}

export async function deployDrawCalculator(
    gaugeControllerAddress: string,
    drawBufferAddress: string,
    prizeConfigHistoryAddress: string,
    owner: string,
): Promise<Contract> {
    const drawCalculatorFactory = await ethers.getContractFactory('DrawCalculatorV3Harness');

    return await drawCalculatorFactory.deploy(
        gaugeControllerAddress,
        drawBufferAddress,
        prizeConfigHistoryAddress,
        owner,
    );
}

function calculateNumberOfWinnersAtIndex(bitRangeSize: number, tierIndex: number): BigNumber {
    // Prize Count = (2**bitRange)**(cardinality-numberOfMatches)
    // if not grand prize: - (2^bitRange)**(cardinality-numberOfMatches-1) - ... (2^bitRange)**(0)
    if (tierIndex > 0) {
        return BigNumber.from(
            (1 << (bitRangeSize * tierIndex)) - (1 << (bitRangeSize * (tierIndex - 1))),
        );
    } else {
        return BigNumber.from(1);
    }
}

function modifyTimestampsWithOffset(timestamps: number[], offset: number): number[] {
    return timestamps.map((timestamp: number) => timestamp - offset);
}

describe('DrawCalculatorV3', () => {
    const debug = newDebug('pt:DrawCalculator.test.ts:calculate()');

    let drawCalculator: Contract;
    let ticket: MockContract;
    let gaugeController: MockContract;
    let drawBuffer: MockContract;
    let prizeConfigHistory: MockContract;
    let owner: any;
    let wallet2: any;
    let wallet3: any;

    let constructorTest = false;

    const encoder = ethers.utils.defaultAbiCoder;

    beforeEach(async () => {
        [owner, wallet2, wallet3] = await getSigners();

        let ticketArtifact = await artifacts.readArtifact('Ticket');
        ticket = await deployMockContract(owner, ticketArtifact.abi);

        let gaugeControllerArtifact = await artifacts.readArtifact('GaugeController');
        gaugeController = await deployMockContract(owner, gaugeControllerArtifact.abi);

        let drawBufferArtifact = await artifacts.readArtifact('DrawBuffer');
        drawBuffer = await deployMockContract(owner, drawBufferArtifact.abi);

        let prizeConfigHistoryArtifact = await artifacts.readArtifact('PrizeConfigHistory');

        prizeConfigHistory = await deployMockContract(owner, prizeConfigHistoryArtifact.abi);

        if (!constructorTest) {
            drawCalculator = await deployDrawCalculator(
                gaugeController.address,
                drawBuffer.address,
                prizeConfigHistory.address,
                owner.address,
            );
        }
    });

    describe('constructor()', () => {
        beforeEach(() => {
            constructorTest = true;
        });

        afterEach(() => {
            constructorTest = false;
        });

        it('should deploy DrawCalculatorV3', async () => {
            const drawCalculatorV3 = await deployDrawCalculator(
                gaugeController.address,
                drawBuffer.address,
                prizeConfigHistory.address,
                owner.address,
            );

            await expect(drawCalculatorV3.deployTransaction)
                .to.emit(drawCalculatorV3, 'Deployed')
                .withArgs(gaugeController.address, drawBuffer.address, prizeConfigHistory.address);
        });

        it('should fail if gaugeController is address zero', async () => {
            await expect(
                deployDrawCalculator(
                    AddressZero,
                    drawBuffer.address,
                    prizeConfigHistory.address,
                    owner.address,
                ),
            ).to.be.revertedWith('DrawCalc/GC-not-zero-address');
        });

        it('should fail if drawBuffer is address zero', async () => {
            await expect(
                deployDrawCalculator(
                    gaugeController.address,
                    AddressZero,
                    prizeConfigHistory.address,
                    owner.address,
                ),
            ).to.be.revertedWith('DrawCalc/DB-not-zero-address');
        });

        it('should fail if prizeConfigHistory is address zero', async () => {
            await expect(
                deployDrawCalculator(
                    gaugeController.address,
                    drawBuffer.address,
                    AddressZero,
                    owner.address,
                ),
            ).to.be.revertedWith('DrawCalc/PCH-not-zero-address');
        });

        it('should fail if owner is address zero', async () => {
            await expect(
                deployDrawCalculator(
                    gaugeController.address,
                    drawBuffer.address,
                    prizeConfigHistory.address,
                    AddressZero,
                ),
            ).to.be.revertedWith('DrawCalc/owner-not-zero-address');
        });
    });

    describe('getDrawBuffer()', () => {
        it('should successfully get draw buffer address', async () => {
            expect(await drawCalculator.getDrawBuffer()).to.equal(drawBuffer.address);
        });
    });

    describe('getPrizeConfigHistory()', () => {
        it('should successfully get gauge controller address', async () => {
            expect(await drawCalculator.getGaugeController()).to.equal(gaugeController.address);
        });
    });

    describe('getPrizeConfigHistory()', () => {
        it('should successfully get prize config history address', async () => {
            expect(await drawCalculator.getPrizeConfigHistory()).to.equal(
                prizeConfigHistory.address,
            );
        });
    });

    describe('calculatePrizeTierFraction()', () => {
        let prizeConfig: PrizeConfig;

        beforeEach(async () => {
            prizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(5),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(10),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);
        });

        it('grand prize gets the full fraction at index 0', async () => {
            const amount = await drawCalculator.calculatePrizeTierFraction(
                prizeConfig.tiers[0],
                prizeConfig.bitRangeSize,
                BigNumber.from(0),
            );

            expect(amount).to.equal(prizeConfig.tiers[0]);
        });

        it('runner up gets part of the fraction at index 1', async () => {
            const amount = await drawCalculator.calculatePrizeTierFraction(
                prizeConfig.tiers[1],
                prizeConfig.bitRangeSize,
                BigNumber.from(1),
            );

            const prizeCount = calculateNumberOfWinnersAtIndex(
                prizeConfig.bitRangeSize.toNumber(),
                1,
            );

            const expectedPrizeFraction = prizeConfig.tiers[1].div(prizeCount);

            expect(amount).to.equal(expectedPrizeFraction);
        });

        it('all prize tier indexes', async () => {
            for (
                let numberOfMatches = 0;
                numberOfMatches < prizeConfig.tiers.length;
                numberOfMatches++
            ) {
                const tierIndex = BigNumber.from(prizeConfig.tiers.length - numberOfMatches - 1); // minus one because we start at 0

                const fraction = await drawCalculator.calculatePrizeTierFraction(
                    prizeConfig.tiers[Number(tierIndex)],
                    prizeConfig.bitRangeSize,
                    tierIndex,
                );

                let prizeCount: BigNumber = calculateNumberOfWinnersAtIndex(
                    prizeConfig.bitRangeSize.toNumber(),
                    tierIndex.toNumber(),
                );

                const expectedPrizeFraction =
                    prizeConfig.tiers[tierIndex.toNumber()].div(prizeCount);

                expect(fraction).to.equal(expectedPrizeFraction);
            }
        });
    });

    describe('numberOfPrizesForIndex()', () => {
        it('calculates the number of prizes at tiers index 0', async () => {
            const bitRangeSize = 2;

            const result = await drawCalculator.numberOfPrizesForIndex(
                bitRangeSize,
                BigNumber.from(0),
            );

            expect(result).to.equal(1); // grand prize
        });

        it('calculates the number of prizes at tiers index 1', async () => {
            const bitRangeSize = 3;

            const result = await drawCalculator.numberOfPrizesForIndex(
                bitRangeSize,
                BigNumber.from(1),
            );

            // Number that match exactly four: 8^1 - 8^0 = 7
            expect(result).to.equal(7);
        });

        it('calculates the number of prizes at tiers index 3', async () => {
            const bitRangeSize = 3;

            const result = await drawCalculator.numberOfPrizesForIndex(
                bitRangeSize,
                BigNumber.from(3),
            );

            // Number that match exactly two: 8^3 - 8^2
            expect(result).to.equal(448);
        });

        it('calculates the number of prizes at all tiers indices', async () => {
            let prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(5),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.5', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            for (let tierIndex = 0; tierIndex < prizeConfig.tiers.length; tierIndex++) {
                const result = await drawCalculator.numberOfPrizesForIndex(
                    prizeConfig.bitRangeSize,
                    tierIndex,
                );

                const expectedNumberOfWinners = calculateNumberOfWinnersAtIndex(
                    prizeConfig.bitRangeSize.toNumber(),
                    tierIndex,
                );

                expect(result).to.equal(expectedNumberOfWinners);
            }
        });
    });

    describe('calculateTierIndex()', () => {
        it('calculates tiers index 0', async () => {
            const prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(5),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

            const bitMasks = await drawCalculator.createBitMasks(
                prizeConfig.matchCardinality,
                prizeConfig.bitRangeSize,
            );

            const winningRandomNumber =
                '0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70';

            const userRandomNumber =
                '0x369ddb959b07c1d22a9bada1f3420961d0e0252f73c0f5b2173d7f7c6fe12b70'; // intentionally same as winning random number

            const prizetierIndex: BigNumber = await drawCalculator.calculateTierIndex(
                userRandomNumber,
                winningRandomNumber,
                bitMasks,
            );

            // all numbers match so grand prize!
            expect(prizetierIndex).to.eq(BigNumber.from(0));
        });

        it('calculates tiers index 1', async () => {
            const prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(2),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

            // 252: 1111 1100
            // 255  1111 1111

            const bitMasks = await drawCalculator.createBitMasks(
                prizeConfig.matchCardinality,
                prizeConfig.bitRangeSize,
            );

            expect(bitMasks.length).to.eq(2); // same as length of matchCardinality
            expect(bitMasks[0]).to.eq(BigNumber.from(15));

            const prizetierIndex: BigNumber = await drawCalculator.calculateTierIndex(
                252,
                255,
                bitMasks,
            );

            // since the first 4 bits do not match the tiers index will be: (matchCardinality - numberOfMatches )= 2-0 = 2
            expect(prizetierIndex).to.eq(prizeConfig.matchCardinality);
        });

        it('calculates tiers index 1', async () => {
            const prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(3),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

            // 527: 0010 0000 1111
            // 271  0001 0000 1111

            const bitMasks = await drawCalculator.createBitMasks(
                prizeConfig.matchCardinality,
                prizeConfig.bitRangeSize,
            );

            expect(bitMasks.length).to.eq(3); // same as length of matchCardinality
            expect(bitMasks[0]).to.eq(BigNumber.from(15));

            const prizetierIndex: BigNumber = await drawCalculator.calculateTierIndex(
                527,
                271,
                bitMasks,
            );

            // since the first 4 bits do not match the tiers index will be: (matchCardinality - numberOfMatches )= 3-2 = 1
            expect(prizetierIndex).to.eq(BigNumber.from(1));
        });
    });

    describe('createBitMasks()', () => {
        it('creates correct 6 bit masks', async () => {
            const prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(6),
                matchCardinality: BigNumber.from(2),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

            const bitMasks = await drawCalculator.createBitMasks(
                prizeConfig.matchCardinality,
                prizeConfig.bitRangeSize,
            );

            expect(bitMasks[0]).to.eq(BigNumber.from(63)); // 111111
            expect(bitMasks[1]).to.eq(BigNumber.from(4032)); // 11111100000
        });

        it('creates correct 4 bit masks', async () => {
            const prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(2),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

            const bitMasks = await drawCalculator.createBitMasks(
                prizeConfig.matchCardinality,
                prizeConfig.bitRangeSize,
            );

            expect(bitMasks[0]).to.eq(BigNumber.from(15)); // 1111
            expect(bitMasks[1]).to.eq(BigNumber.from(240)); // 11110000
        });
    });

    describe('calculateUserPicks()', () => {
        let offsetStartTimestamps: number[];
        let offsetEndTimestamps: number[];

        beforeEach(async () => {
            const prizeConfig: PrizeConfig = {
                bitRangeSize: BigNumber.from(4),
                matchCardinality: BigNumber.from(5),
                drawId: BigNumber.from(1),
                maxPicksPerUser: BigNumber.from(1001),
                tiers: [
                    parseUnits('0.6', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                    parseUnits('0.1', 9),
                ],
                expiryDuration: BigNumber.from(1000),
                poolStakeCeiling: BigNumber.from(1000),
                prize: toWei('1'),
                endTimestampOffset: BigNumber.from(1),
            };

            prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

            await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

            const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
            const winningRandomNumber = utils.solidityKeccak256(
                ['bytes32', 'uint256'],
                [winningNumber, 1],
            );

            const timestamps = [(await provider.getBlock('latest')).timestamp];

            const draw: Draw = newDraw({
                drawId: BigNumber.from(1),
                winningRandomNumber: BigNumber.from(winningRandomNumber),
                timestamp: BigNumber.from(timestamps[0]),
            });

            await drawBuffer.mock.getDraws.returns([draw]);

            offsetStartTimestamps = modifyTimestampsWithOffset(
                timestamps,
                BigNumber.from(1).toNumber(),
            );

            offsetEndTimestamps = modifyTimestampsWithOffset(
                timestamps,
                prizeConfig.endTimestampOffset.toNumber(),
            );

            await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                .returns(BigNumber.from(100));
        });

        it('calculates the correct number of user picks', async () => {
            const ticketBalance = toWei('5');
            const totalSupply = toWei('100000');

            await ticket.mock.getAverageBalancesBetween
                .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                .returns([ticketBalance]); // (user, timestamp): [balance]

            await ticket.mock.getAverageTotalSuppliesBetween
                .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                .returns([totalSupply]);

            const userPicks = await drawCalculator.calculateUserPicks(
                ticket.address,
                owner.address,
                ['1'],
            );

            expect(userPicks[0]).to.equal(BigNumber.from(5));
        });

        it('calculates the correct number of user picks', async () => {
            const ticketBalance = toWei('10000');
            const totalSupply = toWei('100000');

            await ticket.mock.getAverageBalancesBetween
                .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                .returns([ticketBalance]); // (user, timestamp): [balance]

            await ticket.mock.getAverageTotalSuppliesBetween
                .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                .returns([totalSupply]);

            const userPicks = await drawCalculator.calculateUserPicks(
                ticket.address,
                owner.address,
                ['1'],
            );

            expect(userPicks[0]).to.eq(BigNumber.from(10485));
        });
    });

    describe('getTotalPicks()', () => {
        context('with draw 1 set', () => {
            let prizeConfig: PrizeConfig;

            beforeEach(async () => {
                prizeConfig = {
                    bitRangeSize: BigNumber.from(4),
                    matchCardinality: BigNumber.from(5),
                    drawId: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(1001),
                    tiers: [parseUnits('0.8', 9), parseUnits('0.2', 9)],
                    expiryDuration: BigNumber.from(1000),
                    poolStakeCeiling: BigNumber.from(1000),
                    prize: toWei('100'),
                    endTimestampOffset: BigNumber.from(1),
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);
            });

            it('should return the prize pool total number of picks', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(100));

                const totalPicks = await drawCalculator.getTotalPicks(
                    ticket.address,
                    draw.timestamp.sub(1),
                    draw.timestamp.sub(1),
                    prizeConfig.poolStakeCeiling,
                    prizeConfig.bitRangeSize,
                    prizeConfig.matchCardinality,
                );

                expect(totalPicks).to.equal(104857);
            });
        });
    });

    describe('calculate()', () => {
        context('with draw 1 set', () => {
            let prizeConfig: PrizeConfig;

            beforeEach(async () => {
                prizeConfig = {
                    bitRangeSize: BigNumber.from(4),
                    matchCardinality: BigNumber.from(5),
                    drawId: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(1001),
                    tiers: [parseUnits('0.8', 9), parseUnits('0.2', 9)],
                    expiryDuration: BigNumber.from(1000),
                    poolStakeCeiling: BigNumber.from(1000),
                    prize: toWei('100'),
                    endTimestampOffset: BigNumber.from(1),
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);
            });

            it('should calculate and win grand prize', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const pickIndices = [['1']];
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(100));

                const result = await drawCalculator.calculate(
                    ticket.address,
                    owner.address,
                    [draw.drawId],
                    pickIndices,
                );

                expect(result[0][0]).to.equal(toWei('80'));
                const prizeCounts = encoder.decode(['uint256[][]'], result[1]);
                expect(prizeCounts[0][0][0]).to.equal(BigNumber.from(1)); // has a prizeCount = 1 at grand winner index
                assertEmptyArrayOfBigNumbers(prizeCounts[0][0].slice(1));

                debug(
                    'GasUsed for calculate(): ',
                    (
                        await drawCalculator.estimateGas.calculate(
                            ticket.address,
                            owner.address,
                            [draw.drawId],
                            pickIndices,
                        )
                    ).toString(),
                );
            });

            it('should revert with expired draw', async () => {
                // set draw timestamp as now
                // set expiryDuration as 1 second

                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const pickIndices = [['1']];
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                prizeConfig = {
                    bitRangeSize: BigNumber.from(4),
                    matchCardinality: BigNumber.from(5),
                    drawId: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(1001),
                    tiers: [parseUnits('0.8', 9), parseUnits('0.2', 9)],
                    expiryDuration: BigNumber.from(1),
                    poolStakeCeiling: BigNumber.from(1000),
                    prize: toWei('100'),
                    endTimestampOffset: BigNumber.from(1),
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(100));

                await expect(
                    drawCalculator.calculate(
                        ticket.address,
                        owner.address,
                        [draw.drawId],
                        pickIndices,
                    ),
                ).to.revertedWith('DrawCalc/draw-expired');
            });

            it('should revert with repeated pick indices', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const pickIndices = [['1', '1']]; // this isn't valid
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(100));

                await expect(
                    drawCalculator.calculate(
                        ticket.address,
                        owner.address,
                        [draw.drawId],
                        pickIndices,
                    ),
                ).to.revertedWith('DrawCalc/picks-ascending');
            });

            it('can calculate 1000 picks', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];

                const pickIndices = [[...new Array<number>(1000).keys()]];

                const totalSupply = toWei('10000');
                const ticketBalance = toWei('1000'); // 10 percent of total supply

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(100));

                debug(
                    'GasUsed for calculate 1000 picks(): ',
                    (
                        await drawCalculator.estimateGas.calculate(
                            ticket.address,
                            owner.address,
                            [draw.drawId],
                            pickIndices,
                        )
                    ).toString(),
                );
            });

            it('should match all numbers but prize tiers is 0 at index 0', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                prizeConfig = {
                    ...prizeConfig,
                    tiers: [
                        parseUnits('0', 9), // NOTE ZERO here
                        parseUnits('0.2', 9),
                    ],
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const pickIndices = [['1']];
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(100));

                const prizesAwardable = await drawCalculator.calculate(
                    ticket.address,
                    owner.address,
                    [draw.drawId],
                    pickIndices,
                );

                expect(prizesAwardable[0][0]).to.equal(toWei('0'));
            });

            it('should match all numbers but prize tiers is 0 at index 1', async () => {
                prizeConfig = {
                    ...prizeConfig,
                    bitRangeSize: BigNumber.from(2),
                    matchCardinality: BigNumber.from(3),
                    tiers: [
                        parseUnits('0.1', 9), // NOTE ZERO here
                        parseUnits('0', 9),
                        parseUnits('0.2', 9),
                    ],
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const pickIndices = [['1']];
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(
                        '25671298157762322557963155952891969742538148226988266342908289227085909174336',
                    ),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                const prizesAwardable = await drawCalculator.calculate(
                    ticket.address,
                    owner.address,
                    [draw.drawId],
                    pickIndices,
                );

                expect(prizesAwardable[0][0]).to.equal(toWei('0'));
                const prizeCounts = encoder.decode(['uint256[][]'], prizesAwardable[1]);
                expect(prizeCounts[0][0][1]).to.equal(BigNumber.from(1)); // has a prizeCount = 1 at runner up index
                assertEmptyArrayOfBigNumbers(prizeCounts[0][0].slice(2));
            });

            it('runner up matches but tier is 0 at index 1', async () => {
                // cardinality 3
                // matches = 2
                // non zero tiers = 4
                prizeConfig = {
                    ...prizeConfig,
                    bitRangeSize: BigNumber.from(2),
                    matchCardinality: BigNumber.from(3),
                    tiers: [
                        parseUnits('0.1', 9),
                        parseUnits('0', 9), // NOTE ZERO here
                        parseUnits('0.1', 9),
                        parseUnits('0.1', 9),
                    ],
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const pickIndices = [['1']];
                const ticketBalance = toWei('10');
                const totalSupply = toWei('100');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): [balance]

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(
                        '25671298157762322557963155952891969742538148226988266342908289227085909174336',
                    ),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                const prizesAwardable = await drawCalculator.calculate(
                    ticket.address,
                    owner.address,
                    [draw.drawId],
                    pickIndices,
                );

                expect(prizesAwardable[0][0]).to.equal(toWei('0'));
                const prizeCounts = encoder.decode(['uint256[][]'], prizesAwardable[1]);
                expect(prizeCounts[0][0][1]).to.equal(BigNumber.from(1)); // has a prizeCount = 1 at runner up index
                assertEmptyArrayOfBigNumbers(prizeCounts[0][0].slice(2));
            });

            it('should calculate for multiple picks, first pick grand prize winner, second pick no winnings', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [
                    (await provider.getBlock('latest')).timestamp - 10,
                    (await provider.getBlock('latest')).timestamp - 5,
                ];

                const pickIndices = [['1'], ['2']];
                const ticketBalance = toWei('10');
                const ticketBalance2 = toWei('10');
                const totalSupply1 = toWei('100');
                const totalSupply2 = toWei('100');

                const draw1: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                const draw2: Draw = newDraw({
                    drawId: BigNumber.from(2),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[1]),
                });

                await drawBuffer.mock.getDraws.returns([draw1, draw2]);

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                const prizeConfig2: PrizeConfig = {
                    bitRangeSize: BigNumber.from(4),
                    matchCardinality: BigNumber.from(5),
                    drawId: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(1001),
                    tiers: [parseUnits('0.8', 9), parseUnits('0.2', 9)],
                    expiryDuration: BigNumber.from(1000),
                    poolStakeCeiling: BigNumber.from(1000),
                    prize: toWei('20'),
                    endTimestampOffset: BigNumber.from(1),
                };

                prizeConfig2.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                debug(`pushing settings for draw 2...`);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(2).returns(prizeConfig2);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw1.timestamp.sub(1), draw1.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, [offsetStartTimestamps[0]], [offsetEndTimestamps[0]])
                    .returns([ticketBalance]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs([offsetStartTimestamps[0]], [offsetEndTimestamps[0]])
                    .returns([totalSupply1]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw2.timestamp.sub(1), draw2.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, [offsetStartTimestamps[1]], [offsetEndTimestamps[1]])
                    .returns([ticketBalance2]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs([offsetStartTimestamps[1]], [offsetEndTimestamps[1]])
                    .returns([totalSupply2]);

                const result = await drawCalculator.calculate(
                    ticket.address,
                    owner.address,
                    [draw1.drawId, draw2.drawId],
                    pickIndices,
                );

                expect(result[0][0]).to.equal(toWei('80'));
                expect(result[0][1]).to.equal(toWei('0'));

                const prizeCounts = encoder.decode(['uint256[][]'], result[1]);
                expect(prizeCounts[0][0][0]).to.equal(BigNumber.from(1)); // has a prizeCount = 1 at grand winner index for first draw
                expect(prizeCounts[0][1][0]).to.equal(BigNumber.from(0)); // has a prizeCount = 1 at grand winner index for second draw

                debug(
                    'GasUsed for 2 calculate() calls: ',
                    (
                        await drawCalculator.estimateGas.calculate(
                            ticket.address,
                            owner.address,
                            [draw1.drawId, draw2.drawId],
                            pickIndices,
                        )
                    ).toString(),
                );
            });

            it('should not have enough funds for a second pick and revert', async () => {
                // the first draw the user has > 1 pick and the second draw has 0 picks (0.3/100 < 0.5 so rounds down to 0)
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [
                    (await provider.getBlock('latest')).timestamp - 9,
                    (await provider.getBlock('latest')).timestamp - 5,
                ];
                const totalSupply1 = toWei('100');
                const totalSupply2 = toWei('100');

                const pickIndices = [['1'], ['2']];
                const ticketBalance = toWei('6'); // they had 6pc of all tickets

                const prizeConfig: PrizeConfig = {
                    bitRangeSize: BigNumber.from(4),
                    matchCardinality: BigNumber.from(5),
                    drawId: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(1001),
                    tiers: [parseUnits('0.8', 9), parseUnits('0.2', 9)],
                    expiryDuration: BigNumber.from(1000),
                    poolStakeCeiling: BigNumber.from(10000000), // We increase poolStakeCeiling to reduce user picks
                    prize: toWei('100'),
                    endTimestampOffset: BigNumber.from(1),
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                const ticketBalance2 = toWei('0.3'); // they had 0.3pc of all tickets
                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance, ticketBalance2]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply1, totalSupply2]);

                const draw1: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                const draw2: Draw = newDraw({
                    drawId: BigNumber.from(2),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[1]),
                });

                await drawBuffer.mock.getDraws.returns([draw1, draw2]);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(1).returns(prizeConfig);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(2).returns(prizeConfig);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw1.timestamp.sub(1), draw1.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, [offsetStartTimestamps[0]], [offsetEndTimestamps[0]])
                    .returns([ticketBalance]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs([offsetStartTimestamps[0]], [offsetEndTimestamps[0]])
                    .returns([totalSupply1]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw2.timestamp.sub(1), draw2.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, [offsetStartTimestamps[1]], [offsetEndTimestamps[1]])
                    .returns([ticketBalance2]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs([offsetStartTimestamps[1]], [offsetEndTimestamps[1]])
                    .returns([totalSupply2]);

                await expect(
                    drawCalculator.calculate(
                        ticket.address,
                        owner.address,
                        [draw1.drawId, draw2.drawId],
                        pickIndices,
                    ),
                ).to.revertedWith('DrawCalc/insufficient-user-picks');
            });

            it('should revert exceeding max user picks', async () => {
                // maxPicksPerUser is set to 2, user tries to claim with 3 picks
                const winningNumber = utils.solidityKeccak256(['address'], [owner.address]);
                const winningRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 1],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const totalSupply = toWei('100');
                const pickIndices = [['1', '2', '3']];
                const ticketBalance = toWei('6');

                const prizeConfig: PrizeConfig = {
                    bitRangeSize: BigNumber.from(4),
                    matchCardinality: BigNumber.from(5),
                    drawId: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(2),
                    tiers: [parseUnits('0.8', 9), parseUnits('0.2', 9)],
                    expiryDuration: BigNumber.from(1000),
                    poolStakeCeiling: BigNumber.from(1000),
                    prize: toWei('100'),
                    endTimestampOffset: BigNumber.from(1),
                };

                prizeConfig.tiers = fillPrizeTiersWithZeros(prizeConfig.tiers);

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(2),
                    winningRandomNumber: BigNumber.from(winningRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await prizeConfigHistory.mock.getPrizeConfig.withArgs(2).returns(prizeConfig);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                await expect(
                    drawCalculator.calculate(
                        ticket.address,
                        owner.address,
                        [draw.drawId],
                        pickIndices,
                    ),
                ).to.revertedWith('DrawCalc/exceeds-max-user-picks');
            });

            it('should calculate and win nothing', async () => {
                const winningNumber = utils.solidityKeccak256(['address'], [wallet2.address]);
                const userRandomNumber = utils.solidityKeccak256(
                    ['bytes32', 'uint256'],
                    [winningNumber, 112312312],
                );

                const timestamps = [(await provider.getBlock('latest')).timestamp];
                const totalSupply = toWei('100');

                const pickIndices = [['1']];
                const ticketBalance = toWei('10');

                const offsetStartTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    BigNumber.from(1).toNumber(),
                );

                const offsetEndTimestamps = modifyTimestampsWithOffset(
                    timestamps,
                    prizeConfig.endTimestampOffset.toNumber(),
                );

                await ticket.mock.getAverageBalancesBetween
                    .withArgs(owner.address, offsetStartTimestamps, offsetEndTimestamps)
                    .returns([ticketBalance]); // (user, timestamp): balance

                await ticket.mock.getAverageTotalSuppliesBetween
                    .withArgs(offsetStartTimestamps, offsetEndTimestamps)
                    .returns([totalSupply]);

                const draw: Draw = newDraw({
                    drawId: BigNumber.from(1),
                    winningRandomNumber: BigNumber.from(userRandomNumber),
                    timestamp: BigNumber.from(timestamps[0]),
                });

                await drawBuffer.mock.getDraws.returns([draw]);

                await gaugeController.mock.getScaledAverageGaugeBalanceBetween
                    .withArgs(ticket.address, draw.timestamp.sub(1), draw.timestamp.sub(1))
                    .returns(BigNumber.from(1000));

                const prizesAwardable = await drawCalculator.calculate(
                    ticket.address,
                    owner.address,
                    [draw.drawId],
                    pickIndices,
                );

                expect(prizesAwardable[0][0]).to.equal(toWei('0'));
                const prizeCounts = encoder.decode(['uint256[][]'], prizesAwardable[1]);
                // there will always be a prizeCount at matchCardinality index
                assertEmptyArrayOfBigNumbers(
                    prizeCounts[0][0].slice(prizeConfig.matchCardinality.toNumber() + 1),
                );
            });
        });
    });
});
