import { expect, assert } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, constants, Contract, ContractFactory, BigNumber } from 'ethers';
import { artifacts, ethers } from 'hardhat';
import { Address } from 'hardhat-deploy/dist/types';

const { getSigners } = ethers;
const { AddressZero } = constants;
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
    let assetManager: any;
    let dai: Contract;
    let claimableDraw: Contract;
    let drawCalculator: MockContract;

    const DRAW_SAMPLE_CONFIG = {
        randomNumber: 11111,
        timestamp: 1111111111,
        prize: toWei('10'),
    };

    before(async () => {
        [wallet1, wallet2, assetManager] = await getSigners();
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

        const erc20MintableFactory: ContractFactory = await ethers.getContractFactory(
            'ERC20Mintable',
        );

        dai = await erc20MintableFactory.deploy('Dai Stablecoin', 'DAI');
    });

    describe('drawIdToClaimIndex()', () => {
        it('should convert a draw id to a draw index before reaching cardinality', async () => {
            const drawIdToClaimIndex = await claimableDraw.drawIdToClaimIndex(1, 7);
            expect(drawIdToClaimIndex).to.equal(1);
        });

        it('should convert a draw id to a draw index after reaching cardinality', async () => {
            const drawIdToClaimIndex = await claimableDraw.drawIdToClaimIndex(13, 17);
            expect(drawIdToClaimIndex).to.equal(5);
        });
    });

    describe('createDrawClaimsInput()', () => {
        it('should return an array of iterable randomNumbers, timestamps and prizes', async () => {
            // Must pass array with values to match expected Solidity array lengths. They ultimately are overwritten with the draw variables.
            const createDrawClaimsInput = await claimableDraw.createDrawClaimsInput(
                [0],
                drawCalculator.address,
                [0],
                [0],
                [0],
            );
            expect(createDrawClaimsInput[0][0]).to.equal(BigNumber.from(11111));
            expect(createDrawClaimsInput[1][0]).to.equal(1111111111);
            expect(createDrawClaimsInput[2][0]).to.equal(toWei('10'));
            // TODO: Fix a deep equal to remove extra expect statements
            // expect(createDrawClaimsInput)
            // .to.deep.equal([[BigNumber.from(11111)], [1111111111], [toWei('10')]])
        });
    });

    describe('calculateDrawCollectionPayout()', () => {
        it('should return a total payout after calculating a draw collection prize', async () => {
            await drawCalculator.mock.calculate
                .withArgs(
                    wallet1.address,
                    [DRAW_SAMPLE_CONFIG.randomNumber],
                    [DRAW_SAMPLE_CONFIG.timestamp],
                    [DRAW_SAMPLE_CONFIG.prize],
                    '0x',
                )
                .returns([toWei('10')]);
            const calculateDrawCollectionPayout = await claimableDraw.callStatic.calculateDrawCollectionPayout(
                wallet1.address, // _user
                [
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                    BigNumber.from('0'),
                ], // _userClaimedDraws
                [0], // _drawIds
                drawCalculator.address, // _drawCalculator
                '0x', // _data
            );
            expect(calculateDrawCollectionPayout.totalPayout).to.equal(toWei('10'));
        });
    });

    describe('validateDrawPayout()', () => {
        it('should an update draw claim payout history with the full payout amount in index 0', async () => {
            const payoutHistory = [
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
            ];
            const updatedPayoutHistory = await claimableDraw.validateDrawPayout(
                payoutHistory,
                0,
                toWei('10'),
            );
            expect(updatedPayoutHistory[1][0]).to.equal(toWei('10'));
        });

        it('should an update draw claim payout history with the diff payout amount in index 0', async () => {
            const payoutHistory = [
                toWei('5'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
            ];
            const updatedPayoutHistory = await claimableDraw.validateDrawPayout(
                payoutHistory,
                0,
                toWei('10'),
            );
            expect(updatedPayoutHistory[1][0]).to.equal(toWei('5'));
        });
        it('should an update draw claim payout history with the full payout amount in index 7', async () => {
            const payoutHistory = [
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
            ];
            const updatedPayoutHistory = await claimableDraw.validateDrawPayout(
                payoutHistory,
                7,
                toWei('10'),
            );
            expect(updatedPayoutHistory[1][7]).to.equal(toWei('10'));
        });

        it('should an update draw claim payout history with the diff payout amount in index 7', async () => {
            const payoutHistory = [
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                BigNumber.from('0'),
                toWei('5'),
            ];
            const updatedPayoutHistory = await claimableDraw.validateDrawPayout(
                payoutHistory,
                7,
                toWei('10'),
            );
            expect(updatedPayoutHistory[1][7]).to.equal(toWei('5'));
        });
    });

    describe('userDrawPayout()', () => {
        it('should return the user payout for draw before claiming a payout', async () => {
            expect(await claimableDraw.userDrawPayout(wallet1.address, 0)).to.equal('0');
        });

        it('should return the user payout for draw after claiming a payout', async () => {
            await claimableDraw.setUserDrawPayoutHistory(
                wallet1.address,
                [
                    toWei('1'),
                    toWei('2'),
                    toWei('3'),
                    toWei('4'),
                    toWei('5'),
                    toWei('6'),
                    toWei('7'),
                    toWei('8'),
                ],
                8,
            );
            expect(await claimableDraw.userDrawPayout(wallet1.address, 0)).to.equal(toWei('1'));

            expect(await claimableDraw.userDrawPayout(wallet1.address, 7)).to.equal(toWei('8'));
        });
    });

    describe('userDrawPayouts()', () => {
        it('should read an uninitialized userClaimedDraws', async () => {
            const userClaimedDraws = await claimableDraw.userDrawPayouts(wallet1.address);
            expect(userClaimedDraws[0]).to.equal('0');
        });
    });

    describe('getDraw()', () => {
        it('should fail to read non-existent draw', async () => {
            await expect(claimableDraw.getDraw(1)).to.revertedWith(
                'ClaimableDraw/drawid-out-of-bounds',
            );
        });

        it('should read the recently created draw struct which includes the current calculator', async () => {
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
            await expect(
                claimableDrawUnauthorized.setDrawManager(wallet2.address),
            ).to.be.revertedWith('Ownable: caller is not the owner');
        });

        it('should fail to set draw manager with zero address', async () => {
            await expect(claimableDraw.setDrawManager(AddressZero)).to.be.revertedWith(
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
                claimableDrawUnauthorized.setDrawCalculator(AddressZero),
            ).to.be.revertedWith('Ownable: caller is not the owner');
        });

        it('should fail to set draw calculator with zero address', async () => {
            await expect(claimableDraw.setDrawCalculator(AddressZero)).to.be.revertedWith(
                'ClaimableDraw/calculator-not-zero-address',
            );
        });

        it('should fail to set draw calculator with existing draw calculator', async () => {
            await expect(claimableDraw.setDrawCalculator(AddressZero)).to.be.revertedWith(
                'ClaimableDraw/calculator-not-zero-address',
            );
        });

        it('should succeed to set new draw calculator', async () => {
            await expect(claimableDraw.setDrawCalculator(wallet2.address))
                .to.emit(claimableDraw, 'DrawCalculatorSet')
                .withArgs(wallet2.address);
        });
    });

    describe('createDraw()', () => {
        it('should fail to create a new draw when called from non-draw-manager', async () => {
            const claimableDrawWallet2 = claimableDraw.connect(wallet2);
            await expect(
                claimableDrawWallet2.createDraw(
                    DRAW_SAMPLE_CONFIG.randomNumber,
                    DRAW_SAMPLE_CONFIG.timestamp,
                    DRAW_SAMPLE_CONFIG.prize,
                ),
            ).to.be.revertedWith('ClaimableDraw/unauthorized-draw-manager');
        });

        it('should create a new draw and emit DrawSet', async () => {
            await expect(
                await claimableDraw.createDraw(
                    DRAW_SAMPLE_CONFIG.randomNumber,
                    DRAW_SAMPLE_CONFIG.timestamp,
                    DRAW_SAMPLE_CONFIG.prize,
                ),
            )
                .to.emit(claimableDraw, 'DrawSet')
                .withArgs(
                    1,
                    1,
                    DRAW_SAMPLE_CONFIG.randomNumber,
                    DRAW_SAMPLE_CONFIG.timestamp,
                    DRAW_SAMPLE_CONFIG.prize,
                    drawCalculator.address,
                );
        });

        it('should create 7 new draws and return valid next draw id', async () => {
            for (let index = 0; index <= 7; index++) {
                await claimableDraw.createDraw(
                    DRAW_SAMPLE_CONFIG.randomNumber,
                    DRAW_SAMPLE_CONFIG.timestamp,
                    DRAW_SAMPLE_CONFIG.prize,
                );
            }
            expect(await claimableDraw.nextDrawId()).to.equal(9);
            const nextDraw = await claimableDraw.getDraw(8);
            expect(nextDraw.randomNumber).to.equal(DRAW_SAMPLE_CONFIG.randomNumber);
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
                .returns([toWei('100')]);
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
                .returns([toWei('100')]);
            await expect(
                claimableDraw.claim(wallet1.address, [[0]], [AddressZero], ['0x']),
            ).to.be.revertedWith('ClaimableDraw/calculator-address-invalid');
        });

        it('should fail to claim a previously claimed prize', async () => {
            const MOCK_DRAW = { ...DRAW_SAMPLE_CONFIG, payout: toWei('100') };
            await claimableDraw.createDraw(
                MOCK_DRAW.randomNumber,
                MOCK_DRAW.timestamp,
                MOCK_DRAW.prize,
            );

            await drawCalculator.mock.calculate
                .withArgs(
                    wallet1.address,
                    [MOCK_DRAW.randomNumber],
                    [MOCK_DRAW.timestamp],
                    [MOCK_DRAW.prize],
                    '0x',
                )
                .returns([MOCK_DRAW.payout]);
            await claimableDraw.claim(wallet1.address, [[0]], [drawCalculator.address], ['0x']);

            await expect(
                claimableDraw.claim(wallet1.address, [[0]], [drawCalculator.address], ['0x']),
            ).to.be.revertedWith('ClaimableDraw/payout-below-threshold');
        });

        it('should succeed to claim and emit ClaimedDraw event', async () => {
            const MOCK_DRAW = { ...DRAW_SAMPLE_CONFIG, payout: toWei('100') };
            await claimableDraw.createDraw(
                DRAW_SAMPLE_CONFIG.randomNumber,
                DRAW_SAMPLE_CONFIG.timestamp,
                DRAW_SAMPLE_CONFIG.prize,
            );

            await drawCalculator.mock.calculate
                .withArgs(
                    wallet1.address,
                    [MOCK_DRAW.randomNumber],
                    [MOCK_DRAW.timestamp],
                    [MOCK_DRAW.prize],
                    '0x',
                )
                .returns([MOCK_DRAW.payout]);

            await expect(
                claimableDraw.claim(wallet1.address, [[0]], [drawCalculator.address], ['0x']),
            )
                .to.emit(claimableDraw, 'ClaimedDraw')
                .withArgs(wallet1.address, MOCK_DRAW.payout);

            const userClaimedDraws = await claimableDraw.userDrawPayouts(wallet1.address);
            expect(userClaimedDraws[0]).to.equal(toWei('100'));
        });

        it('should create 8 draws and a user claims all draw ids in a single claim', async () => {
            let drawsIds = [];
            let drawRandomNumbers = [];
            let drawTimestamps = [];
            let drawPrizes = [];
            let MOCK_UNIQUE_DRAW;
            const CLAIM_COUNT = 8;

            for (let index = 0; index < CLAIM_COUNT; index++) {
                MOCK_UNIQUE_DRAW = {
                    randomNumber: DRAW_SAMPLE_CONFIG.randomNumber * index,
                    timestamp: DRAW_SAMPLE_CONFIG.timestamp,
                    prize: DRAW_SAMPLE_CONFIG.prize,
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
                .returns([
                    toWei('1'),
                    toWei('2'),
                    toWei('3'),
                    toWei('4'),
                    toWei('5'),
                    toWei('6'),
                    toWei('7'),
                    toWei('8'),
                ]);

            await claimableDraw.claim(
                wallet1.address,
                [drawsIds],
                [drawCalculator.address],
                ['0x'],
            );

            const payoutExpectation = [
                toWei('1'),
                toWei('2'),
                toWei('3'),
                toWei('4'),
                toWei('5'),
                toWei('6'),
                toWei('7'),
                toWei('8'),
            ];
            const payoutHistory = await claimableDraw.userDrawPayouts(wallet1.address);

            for (let index = 0; index < payoutHistory.length; index++) {
                expect(payoutHistory[index]).to.equal(payoutExpectation[index]);
            }

            // TODO: Fix a deep equal to remove extra expect statements
            // expect(await claimableDraw.userDrawPayouts(wallet1.address)).to.equal(payoutExpectation); // FAILS
        });
    });

    describe('depositERC20()', () => {
        let depositAmount: BigNumber;

        beforeEach(async () => {
            depositAmount = toWei('100');

            await dai.mint(assetManager.address, toWei('1000'));
            await dai.connect(assetManager).approve(claimableDraw.address, depositAmount);
        });

        it('should deposit ERC20 tokens', async () => {
            await claimableDraw.setAssetManager(assetManager.address);

            expect(
                await claimableDraw.connect(assetManager).depositERC20(dai.address, depositAmount),
            )
                .to.emit(claimableDraw, 'TransferredERC20')
                .withArgs(assetManager.address, claimableDraw.address, depositAmount, dai.address);
        });

        it('should fail to deposit ERC20 tokens if not assetManager', async () => {
            await expect(claimableDraw.depositERC20(dai.address, depositAmount)).to.be.revertedWith(
                'AssetManager/caller-not-asset-manager',
            );
        });

        it('should fail to deposit ERC20 tokens if token address is address zero', async () => {
            await claimableDraw.setAssetManager(assetManager.address);

            await expect(
                claimableDraw.connect(assetManager).depositERC20(AddressZero, depositAmount),
            ).to.be.revertedWith('ClaimableDraw/ERC20-not-zero-address');
        });
    });

    describe('withdrawERC20()', () => {
        let withdrawAmount: BigNumber;

        beforeEach(async () => {
            withdrawAmount = toWei('100');

            await dai.mint(claimableDraw.address, toWei('1000'));
        });

        it('should withdraw ERC20 tokens', async () => {
            await claimableDraw.setAssetManager(assetManager.address);

            expect(
                await claimableDraw
                    .connect(assetManager)
                    .withdrawERC20(dai.address, wallet1.address, withdrawAmount),
            )
                .to.emit(claimableDraw, 'TransferredERC20')
                .withArgs(claimableDraw.address, wallet1.address, withdrawAmount, dai.address);
        });

        it('should fail to withdraw ERC20 tokens if not assetManager', async () => {
            await expect(
                claimableDraw.withdrawERC20(dai.address, wallet1.address, withdrawAmount),
            ).to.be.revertedWith('AssetManager/caller-not-asset-manager');
        });

        it('should fail to withdraw ERC20 tokens if token address is address zero', async () => {
            await claimableDraw.setAssetManager(assetManager.address);

            await expect(
                claimableDraw
                    .connect(assetManager)
                    .withdrawERC20(AddressZero, wallet1.address, withdrawAmount),
            ).to.be.revertedWith('ClaimableDraw/ERC20-not-zero-address');
        });
    });

    describe('transferERC20()', () => {
        it('should fail to transfer ERC20 tokens if from and to address are the same', async () => {
            await expect(
                claimableDraw.transferERC20(
                    dai.address,
                    wallet1.address,
                    wallet1.address,
                    toWei('100'),
                ),
            ).to.be.revertedWith('ClaimableDraw/from-different-than-to-address');
        });
    });
});
