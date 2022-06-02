import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { artifacts, ethers } from 'hardhat';
import { Artifact } from 'hardhat/types';

import { increaseTime } from './helpers/increaseTime';

const { getSigners, utils } = ethers;
const { parseEther: toWei } = utils;

describe('GaugeController', () => {
    let owner: SignerWithAddress;
    let manager: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let GaugeController: Contract;
    let GaugeReward: MockContract;
    let Token: Contract;

    let GaugeControllerFactory: ContractFactory;
    let GaugeRewardArtifact: Artifact;
    let TokenFactory: ContractFactory;

    const gaugeAddress = '0x0000000000000000000000000000000000000001';

    before(async () => {
        [owner, manager, wallet2] = await getSigners();
        GaugeControllerFactory = await ethers.getContractFactory('GaugeController');
        GaugeRewardArtifact = await artifacts.readArtifact('GaugeReward');
        TokenFactory = await ethers.getContractFactory('ERC20Mintable');
    });

    beforeEach(async () => {
        Token = await TokenFactory.deploy('GaugeToken', 'GaugeToken');

        GaugeController = await GaugeControllerFactory.deploy(
            Token.address,
            '0x0000000000000000000000000000000000000000',
            owner.address
        );

        GaugeReward = await deployMockContract(owner, GaugeRewardArtifact.abi);

        await GaugeController.setGaugeReward(GaugeReward.address);
        await GaugeController.setManager(manager.address);
    });

    /**
     * @description Test deposit(address _to, uint256 _amount) function
     * -= Expected Behavior =-
     * 1. transfer `token` from msg.sender to `address(this)`
     * 2. increase balance of _to address
     * 3. emit a Deposit event
     */
    describe('deposit(address _to, uint256 _amount)', () => {
        it('should SUCCEED to deposit', async () => {
            await Token.mint(owner.address, toWei('100'));
            await Token.approve(GaugeController.address, toWei('100'));
            const tx = await GaugeController.deposit(owner.address, toWei('100'));
            expect(tx.confirmations).to.be.equal(1);
        });
    });

    /**
     * @description Test withdraw(uint256 _amount) function
     * Expected Behavior:
     * 1. decrease `balance` of `msg.sender` address
     * 1. transfer `token` from `address(this)` to `msg.sender`
     * 3. emit a Withdraw event
     */
    describe('withdraw(uint256 _amount)', () => {
        it('should SUCCEED to withdraw funds', async () => {
            await Token.mint(owner.address, toWei('100'));
            await Token.approve(GaugeController.address, toWei('100'));
            await GaugeController.deposit(owner.address, toWei('100'));
            const tx = await GaugeController.withdraw(toWei('100'));
            expect(tx.confirmations).to.be.equal(1);
        });
    });

    /**
     * @description Test increaseGauge(address _gauge, uint256 _amount) function
     * -= Expected Behavior =-
     * 1. decrease `balance` of `msg.sender` address
     * 2. increase `gaugeBalance` of `msg.sender` address
     * 3. increase `gaugeTwab` TWAB with `_amount`
     * 4. update the `gaugeTwab.details` with the updated `twabDetails` object
     * 4. emit a GaugeIncreased event
     */
    describe('increaseGauge(address _gauge, uint256 _amount)', () => {
        it('should SUCCEED to increase gaugeBalance by decreasing staked balance.', async () => {
            await GaugeController.addGauge(gaugeAddress);

            expect(await GaugeController.getGaugeBalance(gaugeAddress)).to.equal('0');

            await Token.mint(owner.address, toWei('100'));
            await Token.approve(GaugeController.address, toWei('100'));

            await GaugeController.deposit(owner.address, toWei('100'));

            await GaugeReward.mock.afterIncreaseGauge
                .withArgs(gaugeAddress, owner.address, toWei('0'))
                .returns();

            const tx = await GaugeController.increaseGauge(gaugeAddress, toWei('100'));

            expect(tx.confirmations).to.equal(1);

            expect(await GaugeController.getGaugeBalance(gaugeAddress)).to.equal(
                '100000000000000000000',
            );
        });

        it('should FAIL to increase gaugeBalance BECAUSE of insufficient balance', async () => {
            await GaugeController.addGauge(gaugeAddress);
            expect(GaugeController.increaseGauge(gaugeAddress, toWei('100'))).to.be.reverted;
        });
    });

    /**
     * @description Test decreaseGauge(address _gauge, uint256 _amount) function
     * -= Expected Behavior =-
     * 1. increase `balance` of `msg.sender` address
     * 2. decrease `gaugeBalance` of `msg.sender` address
     * 3. decrease `gaugeTwab` TWAB with `_amount`
     * 4. update the `gaugeTwab.details` with the updated `twabDetails` object
     * 5. emit a GaugeDecreased event
     */
    describe('decreaseGauge(address _gauge, uint256 _amount)', () => {
        it('should SUCCEED to increase staked balance by decreasing gaugeBalance .', async () => {
            await GaugeController.addGauge(gaugeAddress);

            expect(await GaugeController.getGaugeBalance(gaugeAddress)).to.eq('0');

            await Token.mint(owner.address, toWei('200'));
            await Token.approve(GaugeController.address, toWei('200'));

            await GaugeController.deposit(owner.address, toWei('200'));

            await GaugeReward.mock.afterIncreaseGauge
                .withArgs(gaugeAddress, owner.address, toWei('0'))
                .returns();

            await GaugeController.increaseGauge(gaugeAddress, toWei('200'));

            await GaugeReward.mock.afterDecreaseGauge
                .withArgs(gaugeAddress, owner.address, toWei('200'))
                .returns();

            const tx = await GaugeController.decreaseGauge(gaugeAddress, toWei('100'));

            expect(tx.confirmations).to.be.equal(1);

            expect(await GaugeController.getGaugeBalance(gaugeAddress)).to.eq(
                '100000000000000000000',
            );
        });

        it('should FAIL to increase staked balance BECAUSE of insufficient gaugeBalance.', async () => {
            await GaugeController.addGauge(gaugeAddress);
            expect(GaugeController.decreaseGauge(gaugeAddress, toWei('100'))).to.be.reverted;
        });
    });

    /**
     * @description Test addGaugeWithScale(address _to) function
     * -= Expected Behavior =-
     * 1. require the `msg.sender` to be authorized to add a gauge
     * 2. require the `gauge` DOES NOT exist
     * 3. increase `gaugeTwab` TWAB with `_scale`
     * 4. update the `gaugeTwab.details` with the updated `twabDetails` object
     * 5. emit a AddGaugeWithScale event
     */
     describe('addGauge(address _to)', () => {
        it('should SUCCEED to add gauge to the gaugeScaleTwabs mapping', async () => {
            await GaugeController.addGauge(gaugeAddress);
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq(
                '1000000000000000000',
            );
        });

        it('should FAIL to execute BECAUSE of unauthorized access', async () => {
            const unauthorized = GaugeController.connect(wallet2);
            expect(unauthorized.addGauge(gaugeAddress)).to.be.revertedWith('Ownable/caller-not-owner');
        });
    });

    /**
     * @description Test addGaugeWithScale(address _to, uint256 _scale) function
     * -= Expected Behavior =-
     * 1. require the `msg.sender` to be authorized to add a gauge
     * 2. require the `gauge` DOES NOT exist
     * 3. increase `gaugeTwab` TWAB with `_scale`
     * 4. update the `gaugeTwab.details` with the updated `twabDetails` object
     * 5. emit a AddGaugeWithScale event
     */
    describe('addGaugeWithScale(address _to, uint256 _scale)', () => {
        it('should SUCCEED to add gauge to the gaugeScaleTwabs mapping', async () => {
            await GaugeController.addGaugeWithScale(gaugeAddress, toWei('1'));
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq(
                '1000000000000000000',
            );
        });

        it('should FAIL to execute BECAUSE of unauthorized access', async () => {
            const unauthorized = GaugeController.connect(wallet2);
            expect(unauthorized.addGaugeWithScale(gaugeAddress, toWei('1'))).to.be.revertedWith('Ownable/caller-not-owner');
        });
    });

    /**
     * @description Test removeGauge(address _gauge) function
     * -= Expected Behavior =-
     * 1. require the `msg.sender` to be authorized to remove a gauge
     * 2. require the `gauge` DOES exist.
     * 3. decrease `gaugeTwab` TWAB with using the current TWAB.balance : RESULT is a 0 TWAB the block.timestamp to infinity
     * 4. update the `gaugeTwab.details` with the updated `twabDetails` object
     * 5. emit a RemoveGauge event
     */
    describe('removeGauge(address _gauge)', () => {
        it('should SUCCEED to remove gauge from the gaugeScaleTwabs mapping', async () => {
            await GaugeController.removeGauge(gaugeAddress);
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq('0');
        });

        it('should FAIL to execute BECAUSE of unauthorized access', async () => {
            const unauthorized = GaugeController.connect(wallet2);
            expect(unauthorized.removeGauge(gaugeAddress)).to.be.revertedWith('Ownable/caller-not-owner');
        });
    });

    /**
     * @description Test setGaugeScale(address _gauge, uint256 _scale function
     * -= Expected Behavior =-
     * 1. require the `msg.sender` to be authorized to remove a gauge
     * 2. require the `gauge` DOES exist.
     * 3. IF
     * 3.1
     * 3.2
     * 4. emit a RemoveGauge event
     */
    describe('setGaugeScale(address _gauge, uint256 _scale', () => {
        it('should SUCCEED to INCREASE the scale on EXISTING gauge', async () => {
            await GaugeController.addGauge(gaugeAddress);
            await GaugeController.setGaugeScale(gaugeAddress, toWei('2'));
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq(
                '2000000000000000000',
            );
        });

        it('should SUCCEED to DECREASE the scale on EXISTING gauge', async () => {
            await GaugeController.addGauge(gaugeAddress);
            await GaugeController.setGaugeScale(gaugeAddress, toWei('0.5'));
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq(
                '500000000000000000',
            );
        });

        it('should SUCCEED to DECREASE the scale on EXISTING gauge from MANAGER role', async () => {
            await GaugeController.addGauge(gaugeAddress);
            const gauge = GaugeController.connect(manager);
            await gauge.setGaugeScale(gaugeAddress, toWei('0.5'));
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq(
                '500000000000000000',
            );
        });

        it('should FAIL to execute BECAUSE of unauthorized access', async () => {
            await GaugeController.addGauge(gaugeAddress);
            const unauthorized = GaugeController.connect(wallet2);
            expect(unauthorized.setGaugeScale(gaugeAddress, toWei('2'))).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });
    });

     describe('setGaugeReward(IGaugeReward _gaugeReward)', () => {
        it('should SUCCEED to SET a new GaugeReward address', async () => {
            await GaugeController.addGauge(gaugeAddress);
            await GaugeController.setGaugeReward('0x0000000000000000000000000000000000000001');
            expect(await GaugeController.gaugeReward()).to.eq(
                '0x0000000000000000000000000000000000000001',
            );
        });
        
        it('should SUCCEED to SET a new GaugeReward address from MANAGER role', async () => {
            await GaugeController.addGauge(gaugeAddress);
            const gauge = GaugeController.connect(manager);
            await gauge.setGaugeReward('0x0000000000000000000000000000000000000001');
            expect(await GaugeController.gaugeReward()).to.eq(
                '0x0000000000000000000000000000000000000001',
            );
        });

        it('should FAIL to execute BECAUSE of unauthorized access', async () => {
            const unauthorized = GaugeController.connect(wallet2);
            expect(unauthorized.setGaugeReward('0x0000000000000000000000000000000000000001')).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });
     })

    /**
     * @description Test getGaugeBalance(address _gauge) function
     * -= Expected Behavior =-
     * 1. read `GaugeTwabs.details.balance`
     */
    describe('getGaugeBalance(address _gauge)', () => {
        it('should SUCCEED to READ the GaugeTwabs[gauge].details.balance from EMPTY mapping', async () => {
            expect(
                await GaugeController.getGaugeBalance('0x0000000000000000000000000000000000000002'),
            ).to.eq('0');
        });

        it('should SUCCEED to READ the GaugeTwabs[gauge].details.balance from INITIALIZED mapping', async () => {
            await GaugeController.addGauge(gaugeAddress);
            expect(await GaugeController.getGaugeBalance(gaugeAddress)).to.eq('0');
        });
    });

    /**
     * @description Test getGaugeScaleBalance(address _gauge) function
     * -= Expected Behavior =-
     * 1. read `GaugeScaleTwabs.details.balance`
     */
    describe('getGaugeScaleBalance(address _gauge)', () => {
        it('should SUCCEED to READ the GaugeScaleTwabs[gauge].details.balance from EMPTY mapping', async () => {
            expect(
                await GaugeController.getGaugeBalance('0x0000000000000000000000000000000000000002'),
            ).to.eq('0');
        });

        it('should SUCCEED to READ the GaugeScaleTwabs[gauge].details.balance from INITIALIZED mapping', async () => {
            await GaugeController.addGauge(gaugeAddress);
            expect(await GaugeController.getGaugeScaleBalance(gaugeAddress)).to.eq(
                '1000000000000000000',
            );
        });
    });

    /**
     * @description Test getScaledAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime) function
     * -= Expected Behavior =-
     * 1. read `Gauge` average balance between `_startTime` and `_endTime`
     * 2. read `GaugeScale` average balance between `_startTime` and `_endTime`
     * 3. compute average of `Gauge` and `GaugeScale`
     */
    describe('getScaledAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime)', () => {
        it('should SUCCEED to READ the scaled average of', async () => {
            // Add Gauge with Scale TWAB
            await GaugeController.addGaugeWithScale(gaugeAddress, toWei('1'));

            // Increase Gauge TWAB
            await Token.mint(owner.address, toWei('100'));
            await Token.approve(GaugeController.address, toWei('100'));

            await GaugeController.deposit(owner.address, toWei('100'));

            await GaugeReward.mock.afterIncreaseGauge
                .withArgs(gaugeAddress, owner.address, toWei('0'))
                .returns();

            await GaugeController.increaseGauge(gaugeAddress, toWei('100'));

            // Simulate Increase in Time by 1 Day (86400 seconds)
            await increaseTime(ethers.provider, 86400);
            const timestamp = (await ethers.provider.getBlock('latest')).timestamp;
            const startTime = timestamp - 86400;
            const endTime = timestamp;

            // READ Scaled Gauge TWAB
            const read = await GaugeController.getScaledAverageGaugeBalanceBetween(
                gaugeAddress,
                startTime,
                endTime,
            );

            expect(read).to.eq('100000000000000000000');
        });
    });

    /**
     * @description Test getAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime) function
     * -= Expected Behavior =-
     * 1. read `Gauge` average balance between `_startTime` and `_endTime`
     */
    describe('getAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime)', () => {
        it('should SUCCEED to READ the balance average of the gauge', async () => {
            // Add Gauge with Scale TWAB
            await GaugeController.addGaugeWithScale(gaugeAddress, toWei('1'));

            // Increase Gauge TWAB
            await Token.mint(owner.address, toWei('100'));
            await Token.approve(GaugeController.address, toWei('100'));

            await GaugeController.deposit(owner.address, toWei('100'));

            await GaugeReward.mock.afterIncreaseGauge
                .withArgs(gaugeAddress, owner.address, toWei('0'))
                .returns();

            await GaugeController.increaseGauge(gaugeAddress, toWei('100'));

            // Simulate Increase in Time by 1 Day (86400 seconds)
            await increaseTime(ethers.provider, 86400);
            const timestamp = (await ethers.provider.getBlock('latest')).timestamp;
            const startTime = timestamp - 86400;
            const endTime = timestamp;

            // READ Gauge TWAB
            const read = await GaugeController.getAverageGaugeBalanceBetween(
                gaugeAddress,
                startTime,
                endTime,
            );

            expect(read).to.eq('100000000000000000000');
        });
    });

    /**
     * @description Test getAverageGaugeScaleBetween(address _gauge, uint256 _startTime, uint256 _endTime) function
     * -= Expected Behavior =-
     * 1. read `GaugeScale` average balance between `_startTime` and `_endTime`
     */
    describe('getAverageGaugeScaleBetween(address _gauge, uint256 _startTime, uint256 _endTime)', () => {
        it('should SUCCEED to READ the scale TWAB of the gauge', async () => {
            // Add Gauge with Scale TWAB
            await GaugeController.addGaugeWithScale(gaugeAddress, toWei('1'));

            // Simulate Increase in Time by 1 Day (86400 seconds)
            await increaseTime(ethers.provider, 86400);
            const timestamp = (await ethers.provider.getBlock('latest')).timestamp;
            const startTime = timestamp - 86400;
            const endTime = timestamp;

            // READ Gauge TWAB
            const read = await GaugeController.getAverageGaugeScaleBetween(
                gaugeAddress,
                startTime,
                endTime,
            );
            expect(read).to.eq('1000000000000000000');
        });
    });
});
