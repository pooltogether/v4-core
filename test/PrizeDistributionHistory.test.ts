import { expect } from 'chai';
import { ethers } from 'hardhat';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { PrizeDistributionSettings } from './types';
import { fillPrizeDistributionsWithZeros } from './helpers/fillPrizeDistributionsWithZeros';

const { getSigners } = ethers;

describe('PrizeDistributionHistory', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let prizeDistributionHistory: Contract;

    const prizeDistribution: PrizeDistributionSettings = {
        matchCardinality: BigNumber.from(5),
        numberOfPicks: ethers.utils.parseEther('1'),
        distributions: [ethers.utils.parseUnits('0.5', 9)],
        bitRangeSize: BigNumber.from(3),
        prize: ethers.utils.parseEther('100'),
        startTimestampOffset: BigNumber.from(0),
        endTimestampOffset: BigNumber.from(3600),
        maxPicksPerUser: BigNumber.from(10),
    };

    prizeDistribution.distributions = fillPrizeDistributionsWithZeros(
        prizeDistribution.distributions,
    );

    function newPrizeDistribution(cardinality: number = 5): any {
        return {
            ...prizeDistribution,
            matchCardinality: BigNumber.from(cardinality),
        };
    }

    before(async () => {
        [wallet1, wallet2, wallet3] = await getSigners();
    });

    beforeEach(async () => {
        const prizeDistributionHistoryFactory: ContractFactory = await ethers.getContractFactory(
            'PrizeDistributionHistory',
        );

        prizeDistributionHistory = await prizeDistributionHistoryFactory.deploy(wallet1.address, 3);

        prizeDistribution.distributions = fillPrizeDistributionsWithZeros(
            prizeDistribution.distributions,
        );

        await prizeDistributionHistory.setManager(wallet1.address);
    });

    describe('getNewestPrizeDistribution()', () => {
        it('should error when no draw history', async () => {
            await expect(prizeDistributionHistory.getNewestPrizeDistribution()).to.be.revertedWith(
                'DRB/future-draw',
            );
        });

        it('should get the last draw after pushing a draw', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution(5));

            const settings = await prizeDistributionHistory.getNewestPrizeDistribution();

            expect(settings.prizeDistribution.matchCardinality).to.equal(
                prizeDistribution.matchCardinality,
            );

            expect(settings.drawId).to.equal(1);
        });
    });

    describe('getOldestPrizeDistribution()', () => {
        it('should yield an empty draw when no history', async () => {
            const draw = await prizeDistributionHistory.getOldestPrizeDistribution();

            expect(draw.prizeDistribution.matchCardinality).to.equal(0);
            expect(draw.drawId).to.equal(0);
        });

        it('should yield the first draw when only one', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(5, newPrizeDistribution());

            const draw = await prizeDistributionHistory.getOldestPrizeDistribution();

            expect(draw.prizeDistribution.matchCardinality).to.equal(5);
            expect(draw.drawId).to.equal(5);
        });

        it('should give the first draw when the buffer is not full', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(7, newPrizeDistribution());
            await prizeDistributionHistory.pushPrizeDistribution(8, newPrizeDistribution());

            const draw = await prizeDistributionHistory.getOldestPrizeDistribution();

            expect(draw.prizeDistribution.matchCardinality).to.equal(
                prizeDistribution.matchCardinality,
            );

            expect(draw.drawId).to.equal(7);
        });

        it('should give the first draw when the buffer is full', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(9, newPrizeDistribution(1));
            await prizeDistributionHistory.pushPrizeDistribution(10, newPrizeDistribution(2));
            await prizeDistributionHistory.pushPrizeDistribution(11, newPrizeDistribution(3));

            const draw = await prizeDistributionHistory.getOldestPrizeDistribution();

            expect(draw.prizeDistribution.matchCardinality).to.equal(1);
            expect(draw.drawId).to.equal(9);
        });

        it('should give the oldest draw when the buffer has wrapped', async () => {
            // buffer can only hold 3, so the oldest should be drawId 14
            await prizeDistributionHistory.pushPrizeDistribution(12, newPrizeDistribution(4));
            await prizeDistributionHistory.pushPrizeDistribution(13, newPrizeDistribution(5));
            await prizeDistributionHistory.pushPrizeDistribution(14, newPrizeDistribution(6));
            await prizeDistributionHistory.pushPrizeDistribution(15, newPrizeDistribution(7));
            await prizeDistributionHistory.pushPrizeDistribution(16, newPrizeDistribution(8));

            const draw = await prizeDistributionHistory.getOldestPrizeDistribution();

            expect(draw.prizeDistribution.matchCardinality).to.equal(6);
            expect(draw.drawId).to.equal(14);
        });

        // @TODO: Create PrizeDistributionHistory harness smart contract to expose
        describe('_estimateDrawId()', () => {
            it('should return Draw ID 0 when no history', async () => {});
        });
    });

    describe('pushPrizeDistribution()', () => {
        context('sanity checks', () => {
            let prizeDistribution: PrizeDistributionSettings;

            beforeEach(async () => {
                prizeDistribution = {
                    matchCardinality: BigNumber.from(5),
                    distributions: [
                        ethers.utils.parseUnits('0.6', 9),
                        ethers.utils.parseUnits('0.1', 9),
                        ethers.utils.parseUnits('0.1', 9),
                        ethers.utils.parseUnits('0.1', 9),
                    ],
                    numberOfPicks: BigNumber.from('100'),
                    bitRangeSize: BigNumber.from(4),
                    prize: ethers.utils.parseEther('1'),
                    startTimestampOffset: BigNumber.from(1),
                    endTimestampOffset: BigNumber.from(1),
                    maxPicksPerUser: BigNumber.from(1001),
                };

                prizeDistribution.distributions = fillPrizeDistributionsWithZeros(
                    prizeDistribution.distributions,
                );
            });

            it('should require a sane cardinality', async () => {
                prizeDistribution.matchCardinality = BigNumber.from(3);

                await expect(
                    prizeDistributionHistory.pushPrizeDistribution(1, prizeDistribution),
                ).to.be.revertedWith('DrawCalc/matchCardinality-gte-distributions');
            });

            it('should require a sane bit range', async () => {
                prizeDistribution.matchCardinality = BigNumber.from(32); // means that bit range size max is 8
                prizeDistribution.bitRangeSize = BigNumber.from(9);

                await expect(
                    prizeDistributionHistory.pushPrizeDistribution(1, prizeDistribution),
                ).to.be.revertedWith('DrawCalc/bitRangeSize-too-large');
            });

            it('cannot set over 100pc of prize for distribution', async () => {
                prizeDistribution.distributions[0] = ethers.utils.parseUnits('1', 9);

                await expect(
                    prizeDistributionHistory.pushPrizeDistribution(1, prizeDistribution),
                ).to.be.revertedWith('DrawCalc/distributions-gt-100%');
            });

            it('cannot set bitRangeSize = 0', async () => {
                prizeDistribution.bitRangeSize = BigNumber.from(0);

                await expect(
                    prizeDistributionHistory.pushPrizeDistribution(1, prizeDistribution),
                ).to.be.revertedWith('DrawCalc/bitRangeSize-gt-0');
            });

            it('cannot set matchCardinality = 0', async () => {
                prizeDistribution.matchCardinality = BigNumber.from(0);

                await expect(
                    prizeDistributionHistory.pushPrizeDistribution(1, prizeDistribution),
                ).to.be.revertedWith('DrawCalc/matchCardinality-gt-0');
            });

            it('cannot set maxPicksPerUser = 0', async () => {
                prizeDistribution.maxPicksPerUser = BigNumber.from(0);

                await expect(
                    prizeDistributionHistory.pushPrizeDistribution(1, prizeDistribution),
                ).to.be.revertedWith('DrawCalc/maxPicksPerUser-gt-0');
            });
        });

        it('should fail to create a new draw when called from non-draw-manager', async () => {
            const drawPrizeWallet2 = prizeDistributionHistory.connect(wallet2);

            await expect(
                drawPrizeWallet2.pushPrizeDistribution(1, newPrizeDistribution()),
            ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });

        it('should create a new draw and emit DrawCreated', async () => {
            await expect(
                await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution()),
            ).to.emit(prizeDistributionHistory, 'PrizeDistributionSet');
        });
    });

    describe('getPrizeDistribution()', () => {
        it('should read fail when no draw history', async () => {
            await expect(prizeDistributionHistory.getPrizeDistribution(0)).to.revertedWith(
                'DRB/future-draw',
            );
        });

        it('should read the recently created draw struct', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution(6));

            const draw = await prizeDistributionHistory.getPrizeDistribution(1);

            expect(draw.matchCardinality).to.equal(6);
        });
    });

    describe('getPrizeDistributions()', () => {
        it('should fail to read if draws history is empty', async () => {
            await expect(prizeDistributionHistory.getPrizeDistributions([0])).to.revertedWith(
                'DRB/future-draw',
            );
        });

        it('should successfully read an array of draws', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution(4));
            await prizeDistributionHistory.pushPrizeDistribution(2, newPrizeDistribution(5));
            await prizeDistributionHistory.pushPrizeDistribution(3, newPrizeDistribution(6));

            const draws = await prizeDistributionHistory.getPrizeDistributions([1, 2, 3]);

            for (let index = 0; index < draws.length; index++) {
                expect(draws[index].matchCardinality).to.equal(index + 4);
            }
        });
    });

    describe('getPrizeDistributionCount()', () => {
        it('should return 0 when no draw history', async () => {
            expect(await prizeDistributionHistory.getPrizeDistributionCount()).to.equal(0);
        });

        it('should return 2 if 2 draws have been pushed', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution(4));
            await prizeDistributionHistory.pushPrizeDistribution(2, newPrizeDistribution(5));

            expect(await prizeDistributionHistory.getPrizeDistributionCount()).to.equal(2);
        });

        it('should return 3 if buffer of cardinality 3 is full', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution(4));
            await prizeDistributionHistory.pushPrizeDistribution(2, newPrizeDistribution(5));
            await prizeDistributionHistory.pushPrizeDistribution(3, newPrizeDistribution(6));

            expect(await prizeDistributionHistory.getPrizeDistributionCount()).to.equal(3);
        });

        it('should return 3 if ring buffer has wrapped', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution(4));
            await prizeDistributionHistory.pushPrizeDistribution(2, newPrizeDistribution(5));
            await prizeDistributionHistory.pushPrizeDistribution(3, newPrizeDistribution(6));
            await prizeDistributionHistory.pushPrizeDistribution(4, newPrizeDistribution(7));

            expect(await prizeDistributionHistory.getPrizeDistributionCount()).to.equal(3);
        });
    });

    describe('setPrizeDistribution()', () => {
        it('should fail to set existing draw as unauthorized account', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution());

            await expect(
                prizeDistributionHistory
                    .connect(wallet3)
                    .setPrizeDistribution(1, newPrizeDistribution()),
            ).to.be.revertedWith('Ownable/caller-not-owner');
        });

        it('should fail to set existing draw as manager ', async () => {
            await prizeDistributionHistory.setManager(wallet2.address);
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution());

            await expect(
                prizeDistributionHistory
                    .connect(wallet2)
                    .setPrizeDistribution(1, newPrizeDistribution()),
            ).to.be.revertedWith('Ownable/caller-not-owner');
        });

        it('should succeed to set existing draw as owner', async () => {
            await prizeDistributionHistory.pushPrizeDistribution(1, newPrizeDistribution());

            await expect(
                prizeDistributionHistory.setPrizeDistribution(1, newPrizeDistribution(6)),
            ).to.emit(prizeDistributionHistory, 'PrizeDistributionSet');

            expect(
                (await prizeDistributionHistory.getPrizeDistribution(1)).matchCardinality,
            ).to.equal(6);
        });
    });
});
