import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { BigNumber, Contract } from 'ethers';
import { ethers, artifacts } from 'hardhat';

const { constants, getContractFactory, getSigners, provider, utils } = ethers;
const { AddressZero, MaxUint256, Zero } = constants;
const { parseEther: toWei, parseUnits } = utils;

// 10% cut
const stakerCut = parseUnits('0.1', 9);
const stakerCutInWei = toWei('0.1');

const gaugeRewardAmount = (swapAmount: BigNumber) => swapAmount.mul(stakerCutInWei).div(toWei('1'));

const exchangeRate = (swapAmount: BigNumber, gaugeBalance: BigNumber) =>
    swapAmount.mul(stakerCutInWei).div(gaugeBalance);

const userRewardAmount = (
    swapAmount: BigNumber,
    gaugeBalance: BigNumber,
    userStakeBalance: BigNumber,
) => {
    const userShareOfStake = userStakeBalance.mul(toWei('100')).div(gaugeBalance);

    return gaugeRewardAmount(swapAmount).mul(userShareOfStake).div(toWei('100'));
};

const deployGaugeReward = async (
    gaugeControllerAddress: string,
    vaultAddress: string,
    liquidatorAddress: string,
    stakerCutNumber = stakerCut,
): Promise<Contract> => {
    const gaugeRewardFactory = await getContractFactory('GaugeReward');

    return await gaugeRewardFactory.deploy(
        gaugeControllerAddress,
        vaultAddress,
        liquidatorAddress,
        stakerCutNumber, // 10% staker cut,
    );
};

describe('GaugeReward', () => {
    let gaugeAddress: string;
    let gaugeReward: Contract;
    let gaugeController: MockContract;
    let tokenVault: Contract;
    let poolToken: Contract;
    let usdcToken: Contract;

    let owner: SignerWithAddress;
    let liquidator: SignerWithAddress;

    let constructorTest = false;

    const afterSwap = async (
        token: Contract,
        rewardsAmount: BigNumber,
        gaugeBalance: BigNumber,
        caller = liquidator,
    ) => {
        await token.mint(tokenVault.address, rewardsAmount);

        await tokenVault.setApproval(gaugeReward.address, true);

        const currentAllowance = await token.allowance(tokenVault.address, gaugeReward.address);

        if (currentAllowance.eq(Zero)) {
            await tokenVault.increaseERC20Allowance(token.address, gaugeReward.address, MaxUint256);
        }

        await gaugeController.mock.getGaugeBalance.returns(gaugeBalance);

        return await gaugeReward
            .connect(caller)
            .afterSwap(AddressZero, gaugeAddress, '0', token.address, rewardsAmount);
    };

    beforeEach(async () => {
        [owner, liquidator] = await getSigners();

        gaugeAddress = '0xDe3825B1309E823D52C677E4981a1c67fF0d03E5';

        const ERC20MintableContract = await getContractFactory('ERC20Mintable', owner);
        poolToken = await ERC20MintableContract.deploy('PoolTogether', 'POOL');
        usdcToken = await ERC20MintableContract.deploy('USD Coin', 'USDC');

        let gaugeControllerArtifact = await artifacts.readArtifact('GaugeController');
        gaugeController = await deployMockContract(owner, gaugeControllerArtifact.abi);

        let tokenVaultContract = await getContractFactory('TokenVault', owner);
        tokenVault = await tokenVaultContract.deploy(owner.address);

        if (!constructorTest) {
            gaugeReward = await deployGaugeReward(
                gaugeController.address,
                tokenVault.address,
                liquidator.address,
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

        it('should deploy GaugeReward', async () => {
            const gaugeReward = await deployGaugeReward(
                gaugeController.address,
                tokenVault.address,
                liquidator.address,
            );

            await expect(gaugeReward.deployTransaction)
                .to.emit(gaugeReward, 'Deployed')
                .withArgs(
                    gaugeController.address,
                    tokenVault.address,
                    liquidator.address,
                    stakerCut,
                );
        });

        it('should fail if GaugeController is address zero', async () => {
            await expect(
                deployGaugeReward(AddressZero, tokenVault.address, liquidator.address),
            ).to.be.revertedWith('GReward/GC-not-zero-address');
        });

        it('should fail if Vault is address zero', async () => {
            await expect(
                deployGaugeReward(gaugeController.address, AddressZero, liquidator.address),
            ).to.be.revertedWith('GReward/Vault-not-zero-address');
        });

        it('should fail if Liquidator is address zero', async () => {
            await expect(
                deployGaugeReward(gaugeController.address, tokenVault.address, AddressZero),
            ).to.be.revertedWith('GReward/Liq-not-zero-address');
        });

        it('should fail if staker cut is greater than 8 decimals', async () => {
            await expect(
                deployGaugeReward(
                    gaugeController.address,
                    tokenVault.address,
                    liquidator.address,
                    parseUnits('1', 9),
                ),
            ).to.be.revertedWith('GReward/staker-cut-lt-1e9');
        });
    });

    describe('gaugeController()', () => {
        it('should return GaugeController address', async () => {
            expect(await gaugeReward.gaugeController()).to.equal(gaugeController.address);
        });
    });

    describe('afterSwap()', () => {
        let swapAmount: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            gaugeBalance = toWei('100000');
        });

        it('should add rewards', async () => {
            expect(await afterSwap(poolToken, swapAmount, gaugeBalance))
                .to.emit(gaugeReward, 'RewardsAdded')
                .withArgs(
                    gaugeAddress,
                    poolToken.address,
                    swapAmount,
                    gaugeRewardAmount(swapAmount),
                    exchangeRate(swapAmount, gaugeBalance),
                );
        });

        it('exchangeRate should be 0 if gaugeBalance is equal to 0', async () => {
            expect(await afterSwap(poolToken, swapAmount, Zero))
                .to.emit(gaugeReward, 'RewardsAdded')
                .withArgs(
                    gaugeAddress,
                    poolToken.address,
                    swapAmount,
                    gaugeRewardAmount(swapAmount),
                    Zero,
                );
        });

        it('should fail if not liquidator', async () => {
            await expect(afterSwap(poolToken, swapAmount, gaugeBalance, owner)).to.be.revertedWith(
                'GReward/only-liquidator',
            );
        });
    });

    describe('currentRewardToken()', () => {
        let rewardsAmount: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            rewardsAmount = toWei('1000');
            gaugeBalance = toWei('100000');
        });

        it('should return an empty struct if no reward token has been set yet', async () => {
            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(rewardToken.token).to.equal(AddressZero);
            expect(rewardToken.timestamp).to.equal(0);
        });

        it('should add rewards and return the newly pushed reward token', async () => {
            await gaugeController.mock.getGaugeBalance.returns(gaugeBalance);

            const afterSwapTx = await afterSwap(poolToken, rewardsAmount, gaugeBalance);

            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(afterSwapTx)
                .to.emit(gaugeReward, 'RewardTokenPushed')
                .withArgs(gaugeAddress, poolToken.address, currentTimestamp);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(rewardToken.token).to.equal(poolToken.address);
            expect(rewardToken.timestamp).to.equal(currentTimestamp);
        });

        it('should add rewards twice and return the last pushed reward token', async () => {
            await afterSwap(poolToken, rewardsAmount, gaugeBalance);
            await afterSwap(usdcToken, rewardsAmount, gaugeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);
            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(rewardToken.token).to.equal(usdcToken.address);
            expect(rewardToken.timestamp).to.equal(currentTimestamp);
        });

        it('should add rewards twice and return the only reward token', async () => {
            await afterSwap(poolToken, rewardsAmount, gaugeBalance);

            const firstSwapTimestamp = (await provider.getBlock('latest')).timestamp;

            await afterSwap(poolToken, rewardsAmount, gaugeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(rewardToken.token).to.equal(poolToken.address);
            expect(rewardToken.timestamp).to.equal(firstSwapTimestamp);
        });
    });

    describe('afterIncreaseGauge()', () => {
        let swapAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
        });

        it('should call afterIncreaseGauge', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(
                await gaugeReward.userGaugeRewardTokenLastClaimedTimestamp(
                    owner.address,
                    gaugeAddress,
                    AddressZero,
                ),
            ).to.equal(currentTimestamp);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);
            const exchangeRate = await gaugeReward.gaugeRewardTokenExchangeRates(
                gaugeAddress,
                rewardToken.token,
                rewardToken.timestamp,
            );

            expect(
                await gaugeReward.userGaugeRewardTokenExchangeRates(
                    owner.address,
                    gaugeAddress,
                    rewardToken.token,
                    rewardToken.timestamp,
                ),
            ).to.equal(exchangeRate);
        });

        it('should claim rewards', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            expect(
                await gaugeController.call(
                    gaugeReward,
                    'afterIncreaseGauge',
                    gaugeAddress,
                    owner.address,
                    userStakeBalance,
                ),
            )
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    poolToken.address,
                    owner.address,
                    userRewardAmount(swapAmount, gaugeBalance, userStakeBalance),
                    exchangeRate(swapAmount, gaugeBalance),
                );
        });

        it('should fail if not called by gaugeController', async () => {
            await expect(
                gaugeReward.afterIncreaseGauge(gaugeAddress, owner.address, userStakeBalance),
            ).to.be.revertedWith('GReward/only-GaugeController');
        });
    });

    describe('afterDecreaseGauge()', () => {
        let swapAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
        });

        it('should call afterDecreaseGauge', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterDecreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(
                await await gaugeReward.userGaugeRewardTokenLastClaimedTimestamp(
                    owner.address,
                    gaugeAddress,
                    AddressZero,
                ),
            ).to.equal(currentTimestamp);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);
            const exchangeRate = await gaugeReward.gaugeRewardTokenExchangeRates(
                gaugeAddress,
                rewardToken.token,
                rewardToken.timestamp,
            );

            expect(
                await gaugeReward.userGaugeRewardTokenExchangeRates(
                    owner.address,
                    gaugeAddress,
                    rewardToken.token,
                    rewardToken.timestamp,
                ),
            ).to.equal(exchangeRate);
        });

        it('should claim rewards', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterDecreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            expect(
                await gaugeController.call(
                    gaugeReward,
                    'afterDecreaseGauge',
                    gaugeAddress,
                    owner.address,
                    userStakeBalance,
                ),
            )
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    poolToken.address,
                    owner.address,
                    userRewardAmount(swapAmount, gaugeBalance, userStakeBalance),
                    exchangeRate(swapAmount, gaugeBalance),
                );
        });

        it('should fail if not called by gaugeController', async () => {
            await expect(
                gaugeReward.afterDecreaseGauge(gaugeAddress, owner.address, userStakeBalance),
            ).to.be.revertedWith('GReward/only-GaugeController');
        });
    });

    describe('getRewards()', () => {
        let swapAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
        });

        it('should return 0 if user has no stake', async () => {
            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(Zero);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(await gaugeReward.getRewards(gaugeAddress, rewardToken, owner.address)).to.equal(
                Zero,
            );
        });

        it('should return 0 if no reward token has been added', async () => {
            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(await gaugeReward.getRewards(gaugeAddress, rewardToken, owner.address)).to.equal(
                Zero,
            );
        });

        it('should return rewards for current and past reward token', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(poolToken, swapAmount, gaugeBalance);
            await afterSwap(usdcToken, swapAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const previousRewardToken = await gaugeReward.gaugeRewardTokens(gaugeAddress, 0);
            const currentRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(
                await gaugeReward.getRewards(gaugeAddress, previousRewardToken, owner.address),
            ).to.equal(userRewardAmount(swapAmount, gaugeBalance, userStakeBalance));

            expect(
                await gaugeReward.getRewards(gaugeAddress, currentRewardToken, owner.address),
            ).to.equal(userRewardAmount(swapAmount, gaugeBalance, userStakeBalance));
        });

        it('should return 0 if not eligible to past rewards', async () => {
            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(await gaugeReward.getRewards(gaugeAddress, rewardToken, owner.address)).to.equal(
                Zero,
            );
        });

        it('should return 0 if trying to claim for a reward token that does not exist', async () => {
            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(Zero);

            const claimTimestamp = (await provider.getBlock('latest')).timestamp;

            await gaugeReward.claim(
                gaugeAddress,
                { token: poolToken.address, timestamp: claimTimestamp },
                owner.address,
            );

            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            expect(
                await gaugeReward.getRewards(
                    gaugeAddress,
                    {
                        token: poolToken.address,
                        timestamp: claimTimestamp,
                    },
                    owner.address,
                ),
            ).to.equal(Zero);
        });

        it('should return 0 if trying to claim for a previous reward token when at the time user did not have any stake', async () => {
            await afterSwap(poolToken, swapAmount, gaugeBalance);

            const firstPoolRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(usdcToken, swapAmount, gaugeBalance);

            const usdcRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await afterSwap(poolToken, swapAmount, gaugeBalance);

            const lastPoolRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(Zero);

            expect(
                await gaugeReward.getRewards(gaugeAddress, firstPoolRewardToken, owner.address),
            ).to.equal(Zero);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            expect(
                await gaugeReward.getRewards(gaugeAddress, usdcRewardToken, owner.address),
            ).to.equal(userRewardAmount(swapAmount, gaugeBalance, userStakeBalance));

            expect(
                await gaugeReward.getRewards(gaugeAddress, lastPoolRewardToken, owner.address),
            ).to.equal(userRewardAmount(swapAmount, gaugeBalance, userStakeBalance));
        });

        it('should return 0 if gaugeBalance is equal to 0', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(usdcToken, swapAmount, Zero);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const currentRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            expect(
                await gaugeReward.getRewards(gaugeAddress, currentRewardToken, owner.address),
            ).to.equal(Zero);
        });
    });

    describe('claim()', () => {
        let swapAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
        });

        it('should claim rewards', async () => {
            // Alice increases her stake
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            // Bob swaps tokens through the PrizePoolLiquidator
            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            // Alice claims her share of rewards earned from the swap
            expect(await gaugeReward.claim(gaugeAddress, rewardToken, owner.address))
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    rewardToken.token,
                    owner.address,
                    userRewardAmount(swapAmount, gaugeBalance, userStakeBalance),
                    exchangeRate(swapAmount, gaugeBalance),
                );
        });

        it('should claim past rewards', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(poolToken, swapAmount, gaugeBalance);

            const previousRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await afterSwap(usdcToken, swapAmount, gaugeBalance);

            const currentRewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            await expect(gaugeReward.claim(gaugeAddress, previousRewardToken, owner.address))
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    previousRewardToken.token,
                    owner.address,
                    userRewardAmount(swapAmount, gaugeBalance, userStakeBalance),
                    exchangeRate(swapAmount, gaugeBalance),
                );

            await expect(gaugeReward.claim(gaugeAddress, currentRewardToken, owner.address))
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    currentRewardToken.token,
                    owner.address,
                    userRewardAmount(swapAmount, gaugeBalance, userStakeBalance),
                    exchangeRate(swapAmount, gaugeBalance),
                );
        });

        it('should not be eligible to claim past rewards', async () => {
            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            expect(await gaugeReward.claimAll(gaugeAddress, owner.address))
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    poolToken.address,
                    owner.address,
                    Zero,
                    exchangeRate(swapAmount, gaugeBalance),
                );
        });

        it('should not claim any rewards if gaugeBalance is equal to 0', async () => {
            await afterSwap(poolToken, swapAmount, Zero);

            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            expect(await gaugeReward.claimAll(gaugeAddress, owner.address))
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(
                    gaugeAddress,
                    poolToken.address,
                    owner.address,
                    Zero,
                    Zero,
                );
        });
    });

    describe('redeem()', () => {
        let swapAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
        });

        it('should redeem accumulated rewards', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(poolToken, swapAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await gaugeReward.claim(gaugeAddress, rewardToken, owner.address);

            const gaugeRewardAmount = await gaugeReward.userRewardTokenBalances(
                owner.address,
                rewardToken.token,
            );

            expect(await gaugeReward.redeem(owner.address, rewardToken.token))
                .to.emit(gaugeReward, 'RewardsRedeemed')
                .withArgs(owner.address, owner.address, rewardToken.token, gaugeRewardAmount);
        });

        it('should not redeem any rewards if gauge balance is equal to 0', async () => {
            await gaugeController.call(
                gaugeReward,
                'afterIncreaseGauge',
                gaugeAddress,
                owner.address,
                userStakeBalance,
            );

            await afterSwap(poolToken, swapAmount, Zero);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gaugeAddress, owner.address)
                .returns(userStakeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gaugeAddress);

            await gaugeReward.claim(gaugeAddress, rewardToken, owner.address);

            expect(await gaugeReward.redeem(owner.address, rewardToken.token))
                .to.emit(gaugeReward, 'RewardsRedeemed')
                .withArgs(owner.address, owner.address, rewardToken.token, Zero);
        });
    });
});
