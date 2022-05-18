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
): Promise<Contract> => {
    const gaugeRewardFactory = await getContractFactory('GaugeReward');

    return await gaugeRewardFactory.deploy(gaugeControllerAddress, vaultAddress);
};

describe('GaugeReward', () => {
    let gauge: string;
    let gaugeReward: Contract;
    let gaugeController: MockContract;
    let vault: MockContract;
    let poolToken: Contract;
    let usdcToken: Contract;

    let owner: SignerWithAddress;
    let wallet2: SignerWithAddress;

    let constructorTest = false;

    const addRewards = async (
        token: Contract,
        rewardsAmount: BigNumber,
        gaugeBalance: BigNumber,
    ) => {
        await token.mint(owner.address, rewardsAmount);

        await vault.mock.increaseERC20Allowance
            .withArgs(token.address, gaugeReward.address, MaxUint256)
            .returns();

        await gaugeController.mock.getGaugeBalance.returns(gaugeBalance);

        await token.approve(gaugeReward.address, MaxUint256);

        return await gaugeReward.addRewards(gauge, token.address, rewardsAmount);
    };

    beforeEach(async () => {
        [owner, wallet2] = await getSigners();

        gauge = '0xDe3825B1309E823D52C677E4981a1c67fF0d03E5';

        const ERC20MintableContract = await getContractFactory('ERC20Mintable', owner);
        poolToken = await ERC20MintableContract.deploy('PoolTogether', 'POOL');
        usdcToken = await ERC20MintableContract.deploy('USD Coin', 'USDC');

        let gaugeControllerArtifact = await artifacts.readArtifact('GaugeController');
        gaugeController = await deployMockContract(owner, gaugeControllerArtifact.abi);

        let vaultArtifact = await artifacts.readArtifact('IVault');
        vault = await deployMockContract(owner, vaultArtifact.abi);

        if (!constructorTest) {
            gaugeReward = await deployGaugeReward(gaugeController.address, vault.address);
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
            const gaugeReward = await deployGaugeReward(gaugeController.address, vault.address);

            await expect(gaugeReward.deployTransaction)
                .to.emit(gaugeReward, 'Deployed')
                .withArgs(gaugeController.address, vault.address);
        });

        it('should fail if GaugeController is address zero', async () => {
            await expect(deployGaugeReward(AddressZero, vault.address)).to.be.revertedWith(
                'GReward/GC-not-zero-address',
            );
        });

        it('should fail if Vault is address zero', async () => {
            await expect(
                deployGaugeReward(gaugeController.address, AddressZero),
            ).to.be.revertedWith('GReward/Vault-not-zero-address');
        });
    });

    describe('gaugeController()', () => {
        it('should return GaugeController address', async () => {
            expect(await gaugeReward.gaugeController()).to.equal(gaugeController.address);
        });
    });

    describe('addRewards()', () => {
        it.only('should add rewards', async () => {
            const rewardsAmount = toWei('1000');
            const gaugeBalance = toWei('100000');
            const exchangeRate = rewardsAmount.mul(toWei('1')).div(gaugeBalance);

            expect(await addRewards(poolToken, rewardsAmount, gaugeBalance))
                .to.emit(gaugeReward, 'RewardsAdded')
                .withArgs(gauge, poolToken.address, vault.address, rewardsAmount, exchangeRate);

            expect(await poolToken.balanceOf(vault.address)).to.equal(rewardsAmount);
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

        it.only('should add rewards and return the newly added reward token', async () => {
            await gaugeController.mock.getGaugeBalance.returns(gaugeBalance);

            const addRewardsTx = await addRewards(poolToken, rewardsAmount, gaugeBalance);

            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(addRewardsTx)
                .to.emit(gaugeReward, 'RewardTokenPushed')
                .withArgs(gauge, poolToken.address, currentTimestamp);

            const rewardToken = await gaugeReward.currentRewardToken(gauge);

            expect(rewardToken.token).to.equal(poolToken.address);
            expect(rewardToken.timestamp).to.equal(currentTimestamp);
        });

        it.only('should add rewards twice and return the last added reward token', async () => {
            await addRewards(poolToken, rewardsAmount, gaugeBalance);
            await addRewards(usdcToken, rewardsAmount, gaugeBalance);

            const rewardToken = await gaugeReward.currentRewardToken(gauge);
            const currentTimestamp = (await provider.getBlock('latest')).timestamp;

            expect(rewardToken.token).to.equal(usdcToken.address);
            expect(rewardToken.timestamp).to.equal(currentTimestamp);
        });
    });

    describe('claim()', () => {
        let rewardsAmount: BigNumber;
        let userStakeBalance: BigNumber;
        let gaugeBalance: BigNumber;
        let exchangeRate: BigNumber;

        beforeEach(() => {
            rewardsAmount = toWei('1000');
            userStakeBalance = toWei('100');
            gaugeBalance = toWei('100000');
            exchangeRate = rewardsAmount.mul(toWei('1')).div(gaugeBalance);
        });

        it.only('should claim rewards ', async () => {
            await addRewards(poolToken, rewardsAmount, gaugeBalance);

            await gaugeController.mock.getUserGaugeBalance
                .withArgs(gauge, owner.address)
                .returns(userStakeBalance);

            const claimTx = await gaugeReward.claim(gauge, poolToken.address, owner.address);

            console.log('exchangeRate', exchangeRate);

            expect(claimTx)
                .to.emit(gaugeReward, 'RewardsClaimed')
                .withArgs(gauge, poolToken.address, owner.address, rewardsAmount, exchangeRate);
        });
    });
});
