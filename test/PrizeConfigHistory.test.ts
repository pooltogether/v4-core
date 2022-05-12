import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, Contract, ContractFactory } from 'ethers';

import { range } from './helpers/range';
import { PrizeConfig } from './types';

const { getSigners, utils } = ethers;
const { parseEther: toWei } = utils;

describe('PrizeConfigHistory', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;

    let PrizeConfigHistory: Contract;
    let PrizeConfigHistoryFactory: ContractFactory;

    const prizeConfigs: PrizeConfig[] = [
        {
            bitRangeSize: BigNumber.from(5),
            matchCardinality: BigNumber.from(10),
            drawId: BigNumber.from(1),
            maxPicksPerUser: BigNumber.from(10),
            tiers: range(16, 0).map((i) => BigNumber.from(0)),
            expiryDuration: BigNumber.from(10000),
            poolStakeCeiling: BigNumber.from(1000),
            prize: toWei('10000'),
            endTimestampOffset: BigNumber.from(3000),
        },
        {
            bitRangeSize: BigNumber.from(5),
            matchCardinality: BigNumber.from(10),
            drawId: BigNumber.from(6),
            maxPicksPerUser: BigNumber.from(10),
            tiers: range(16, 0).map((i) => BigNumber.from(0)),
            expiryDuration: BigNumber.from(10000),
            poolStakeCeiling: BigNumber.from(1000),
            prize: toWei('10000'),
            endTimestampOffset: BigNumber.from(3000),
        },
        {
            bitRangeSize: BigNumber.from(5),
            matchCardinality: BigNumber.from(10),
            drawId: BigNumber.from(9),
            maxPicksPerUser: BigNumber.from(10),
            tiers: range(16, 0).map((i) => BigNumber.from(0)),
            expiryDuration: BigNumber.from(10000),
            poolStakeCeiling: BigNumber.from(1000),
            prize: toWei('10000'),
            endTimestampOffset: BigNumber.from(3000),
        },
        {
            bitRangeSize: BigNumber.from(5),
            matchCardinality: BigNumber.from(10),
            drawId: BigNumber.from(20),
            maxPicksPerUser: BigNumber.from(10),
            tiers: range(16, 0).map((i) => BigNumber.from(0)),
            expiryDuration: BigNumber.from(10000),
            poolStakeCeiling: BigNumber.from(1000),
            prize: toWei('10000'),
            endTimestampOffset: BigNumber.from(3000),
        },
    ];

    const pushPrizeConfigs = async () => {
        await Promise.all(
            prizeConfigs.map(async (tier) => {
                await PrizeConfigHistory.push(tier);
            }),
        );
    };

    before(async () => {
        [wallet1, wallet2, wallet3] = await getSigners();
        PrizeConfigHistoryFactory = await ethers.getContractFactory('PrizeConfigHistory');
    });

    beforeEach(async () => {
        PrizeConfigHistory = await PrizeConfigHistoryFactory.deploy(wallet1.address, []);
    });

    describe('Getters', () => {
        it('should succeed to get history length', async () => {
            await pushPrizeConfigs();
            const count = await PrizeConfigHistory.count();
            expect(count).to.equal(4);
        });

        it('should succeed to get oldest Draw Id', async () => {
            await pushPrizeConfigs();
            const oldestDrawId = await PrizeConfigHistory.getOldestDrawId();
            expect(oldestDrawId).to.equal(1);
        });

        it('should succeed to get newest Draw Id', async () => {
            await pushPrizeConfigs();
            const newestDrawId = await PrizeConfigHistory.getNewestDrawId();
            expect(newestDrawId).to.equal(20);
        });

        it('should succeed to get a PrizeConfig using an index position', async () => {
            await pushPrizeConfigs();
            const prizeConfig = await PrizeConfigHistory.getPrizeConfigAtIndex(3);
            expect(prizeConfig.drawId).to.equal(20);
        });

        it('should succeed to get prize tiers from history', async () => {
            await pushPrizeConfigs();
            const prizeConfigFromHistory = await PrizeConfigHistory.getPrizeConfigList([3, 7, 9]);
            expect(prizeConfigFromHistory[0].drawId).to.equal(1);
            expect(prizeConfigFromHistory[1].drawId).to.equal(6);
            expect(prizeConfigFromHistory[2].drawId).to.equal(9);
        });

        it('should return prize tier before our searched draw id', async () => {
            await pushPrizeConfigs();
            const prizeConfigFromHistory = await PrizeConfigHistory.getPrizeConfig(4);
            expect(prizeConfigFromHistory.drawId).to.equal(prizeConfigs[0].drawId);
        });

        it('should fail to get a PrizeConfig before history range', async () => {
            await pushPrizeConfigs();
            await expect(PrizeConfigHistory.getPrizeConfig(0)).to.revertedWith(
                'PrizeConfHistory/draw-id-gt-zero',
            );
        });

        it('should fail to get a PrizeTer after history range', async () => {
            await PrizeConfigHistory.push(prizeConfigs[2]);
            await expect(PrizeConfigHistory.getPrizeConfig(4)).to.be.revertedWith(
                'BinarySearchLib/draw-id-out-of-range',
            );
        });
    });

    describe('Setters', () => {
        describe('.push()', () => {
            it('should succeed push PrizeConfig into history from Owner wallet.', async () => {
                await expect(PrizeConfigHistory.push(prizeConfigs[0])).to.emit(
                    PrizeConfigHistory,
                    'PrizeConfigPushed',
                );
            });

            it('should succeed to push PrizeConfig into history from Manager wallet', async () => {
                await PrizeConfigHistory.setManager(wallet2.address);
                await expect(
                    PrizeConfigHistory.connect(wallet2 as unknown as Signer).push(prizeConfigs[0]),
                ).to.emit(PrizeConfigHistory, 'PrizeConfigPushed');
            });

            it('should fail to push PrizeConfig into history with a non-sequential-id', async () => {
                await pushPrizeConfigs();
                await expect(
                    PrizeConfigHistory.push({ ...prizeConfigs[3], drawId: 18 }),
                ).to.be.revertedWith('PrizeConfHistory/nonsequentialId');
            });

            it('should fail to push PrizeConfig into history from Unauthorized wallet', async () => {
                await expect(
                    PrizeConfigHistory.connect(wallet3 as unknown as Signer).push(prizeConfigs[0]),
                ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
            });
        });

        describe('.set()', () => {
            it('should succeed to set existing PrizeConfig in history from Owner wallet.', async () => {
                await pushPrizeConfigs();
                const prizeConfig = {
                    ...prizeConfigs[2],
                    drawId: 20,
                    bitRangeSize: 16,
                };

                await expect(PrizeConfigHistory.popAndPush(prizeConfig)).to.emit(
                    PrizeConfigHistory,
                    'PrizeConfigSet',
                );
            });

            it('should succeed to set newest PrizeConfig in history from Owner wallet.', async () => {
                await pushPrizeConfigs();
                const prizeConfig = {
                    ...prizeConfigs[2],
                    drawId: 20,
                    bitRangeSize: 16,
                };

                await expect(PrizeConfigHistory.popAndPush(prizeConfig)).to.emit(
                    PrizeConfigHistory,
                    'PrizeConfigSet',
                );
            });

            it('should fail to set existing PrizeConfig in history due to invalid draw id', async () => {
                await pushPrizeConfigs();
                const prizeConfig = {
                    ...prizeConfigs[0],
                    drawId: 8,
                    bitRangeSize: 16,
                };

                await expect(PrizeConfigHistory.popAndPush(prizeConfig)).to.revertedWith(
                    'PrizeConfHistory/invalid-draw-id',
                );
            });

            it('should fail to set existing PrizeConfig due to empty history', async () => {
                await expect(PrizeConfigHistory.popAndPush(prizeConfigs[0])).to.revertedWith(
                    'PrizeConfHistory/history-empty',
                );
            });

            it('should fail to set existing PrizeConfig in history from Manager wallet', async () => {
                await expect(
                    PrizeConfigHistory.connect(wallet2 as unknown as Signer).popAndPush(
                        prizeConfigs[0],
                    ),
                ).to.revertedWith('Ownable/caller-not-owner');
            });
        });
    });

    describe('replace()', async () => {
        it('should successfully emit PrizeConfigSet event when replacing an existing PrizeConfig', async () => {
            await pushPrizeConfigs();
            await expect(await PrizeConfigHistory.replace(prizeConfigs[1])).to.emit(
                PrizeConfigHistory,
                'PrizeConfigSet',
            );
        });

        it('should successfully return new values after replacing an existing PrizeConfig', async () => {
            await pushPrizeConfigs();
            const prizeConfig = {
                ...prizeConfigs[1],
                bitRangeSize: 12,
            };

            await PrizeConfigHistory.replace(prizeConfig);

            const prizeConfigVal = await PrizeConfigHistory.getPrizeConfig(prizeConfig.drawId);
            expect(prizeConfigVal.bitRangeSize).to.equal(12);
        });

        it('should fail to replace a PrizeConfig because history is empty', async () => {
            await expect(PrizeConfigHistory.replace(prizeConfigs[1])).to.be.revertedWith(
                'PrizeConfHistory/no-prize-conf',
            );
        });

        it('should fail to replace a PrizeConfig that is out of rance', async () => {
            await PrizeConfigHistory.push(prizeConfigs[3]);
            await expect(PrizeConfigHistory.replace(prizeConfigs[0])).to.be.revertedWith(
                'PrizeConfHistory/drawId-beyond',
            );
        });

        it('should fail to replace a non-existent PrizeConfig', async () => {
            await pushPrizeConfigs();
            const prizeConfig = {
                ...prizeConfigs[1],
                drawId: 4,
            };

            await expect(PrizeConfigHistory.replace(prizeConfig)).to.be.revertedWith(
                'PrizeConfHistory/drawId-mismatch',
            );
        });
    });
});
