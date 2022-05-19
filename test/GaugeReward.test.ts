import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { BigNumber, Contract } from 'ethers';
import { ethers, artifacts } from 'hardhat';

import { fillPrizeTiersWithZeros } from './helpers/fillPrizeTiersWithZeros';

const { constants, getContractFactory, getSigners, provider, utils } = ethers;
const { AddressZero, MaxUint256 } = constants;
const { parseEther: toWei, parseUnits } = utils;

const deployGaugeReward = async (
    gaugeControllerAddress: string,
    vaultAddress: string,
    liquidatorAddress: string
): Promise<Contract> => {
    const gaugeRewardFactory = await getContractFactory('GaugeReward');

    return await gaugeRewardFactory.deploy(gaugeControllerAddress, vaultAddress, liquidatorAddress, ethers.utils.parseUnits('0.1', 9));
};

describe('GaugeReward', () => {
    let gauge: string;
    let gaugeReward: Contract;
    let gaugeController: MockContract;
    let poolToken: Contract;
    let usdcToken: Contract;
    
    let owner: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let liquidator: SignerWithAddress;
    let vault: SignerWithAddress;

    let constructorTest = false;

    const afterSwap = async (
        token: Contract,
        rewardsAmount: BigNumber,
        gaugeBalance: BigNumber,
    ) => {
        await token.mint(vault.address, rewardsAmount);
        await token.approve(gaugeReward.address, MaxUint256);
        await token.connect(vault).approve(gaugeReward.address, MaxUint256);

        await gaugeController.mock.getGaugeBalance.returns(gaugeBalance);

        return await gaugeReward.connect(liquidator).afterSwap(AddressZero, gauge, '0', token.address, rewardsAmount);
    };

    beforeEach(async () => {
        [owner, wallet2, liquidator, vault] = await getSigners();

        gauge = '0xDe3825B1309E823D52C677E4981a1c67fF0d03E5';

        const ERC20MintableContract = await getContractFactory('ERC20Mintable', owner);
        poolToken = await ERC20MintableContract.deploy('PoolTogether', 'POOL');
        usdcToken = await ERC20MintableContract.deploy('USD Coin', 'USDC');

        let gaugeControllerArtifact = await artifacts.readArtifact('GaugeController');
        gaugeController = await deployMockContract(owner, gaugeControllerArtifact.abi);

        if (!constructorTest) {
            gaugeReward = await deployGaugeReward(gaugeController.address, vault.address, liquidator.address);
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
            const gaugeReward = await deployGaugeReward(gaugeController.address, vault.address, liquidator.address);

            await expect(gaugeReward.deployTransaction)
                .to.emit(gaugeReward, 'Deployed')
                .withArgs(gaugeController.address, vault.address);
        });

        it('should fail if GaugeController is address zero', async () => {
            await expect(deployGaugeReward(AddressZero, vault.address, liquidator.address)).to.be.revertedWith(
                'GReward/GC-not-zero-address',
            );
        });

        it('should fail if Vault is address zero', async () => {
            await expect(
                deployGaugeReward(gaugeController.address, AddressZero, liquidator.address),
            ).to.be.revertedWith('GReward/Vault-not-zero-address');
        });
    });

    describe('gaugeController()', () => {
        it('should return GaugeController address', async () => {
            expect(await gaugeReward.gaugeController()).to.equal(gaugeController.address);
        });
    });

    describe('afterSwap()', () => {
        it('should add rewards', async () => {
            const swapAmount = toWei('1000');
            const rewardAmount = swapAmount.div('10') // 10% cut
            const gaugeBalance = toWei('100000');
            const exchangeRate = rewardAmount.mul(toWei('1')).div(gaugeBalance);

            // cut is 10%
            expect(await afterSwap(poolToken, swapAmount, gaugeBalance))
                .to.emit(gaugeReward, 'RewardsAdded')
                .withArgs(gauge, poolToken.address, rewardAmount, exchangeRate);
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
            const rewardToken = await gaugeReward.currentRewardToken(gauge);

            expect(rewardToken.token).to.equal(AddressZero);
            expect(rewardToken.timestamp).to.equal(0);
        });

        it('should add rewards and return the newly added reward token', async () => {
            await gaugeController.mock.getGaugeBalance.returns(gaugeBalance);

            const afterSwapTx = await afterSwap(poolToken, rewardsAmount, gaugeBalance);

            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(afterSwapTx)
                .to.emit(gaugeReward, 'RewardTokenPushed')
                .withArgs(gauge, poolToken.address, currentTimestamp);

            const rewardToken = await gaugeReward.currentRewardToken(gauge);

            expect(rewardToken.token).to.equal(poolToken.address);
            expect(rewardToken.timestamp).to.equal(currentTimestamp);
        });

        it('should add rewards twice and return the last added reward token', async () => {
            await afterSwap(poolToken, rewardsAmount, gaugeBalance);
            await afterSwap(usdcToken, rewardsAmount, gaugeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gauge);
            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(rewardToken.token).to.equal(usdcToken.address);
            expect(rewardToken.timestamp).to.equal(currentTimestamp);
        });
    });

    describe('claim()', () => {
        let swapAmount: BigNumber;
        let rewardAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;
        let exchangeRate: BigNumber;

        beforeEach(() => {
            swapAmount = toWei('1000');
            rewardAmount = swapAmount.div('10') // 10% cut
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
            exchangeRate = rewardAmount.mul(toWei('1')).div(gaugeBalance);
        });

        it('should claim rewards ', async () => {

            await gaugeController.call(gaugeReward, 'afterIncreaseGauge', gauge, owner.address, userStakeBalance)

            await afterSwap(poolToken, swapAmount, gaugeBalance);
            
            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gauge, owner.address)
                .returns(userStakeBalance);

            const claimTx = await gaugeReward.claim(gauge, poolToken.address, owner.address);
            expect(claimTx)
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(gauge, poolToken.address, owner.address, rewardAmount.div('1000'), exchangeRate);
        });
    });
});
