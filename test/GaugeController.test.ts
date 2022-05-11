import { ethers } from 'hardhat';
import { expect } from 'chai';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract, ContractFactory } from 'ethers';
import { utils } from 'ethereum-waffle/node_modules/ethers';
import { increaseTime } from './helpers/increaseTime';

const { getSigners } = ethers;

describe('GaugeController', () => {
    let wallet1: SignerWithAddress;
    let GaugeController: Contract;
    let Token: Contract;
    
    let GaugeControllerFactory: ContractFactory;
    let TokenFactory: ContractFactory;

    before(async () => {
        [wallet1] = await getSigners();
        GaugeControllerFactory = await ethers.getContractFactory(
            'GaugeController'
        );
        TokenFactory = await ethers.getContractFactory('ERC20Mintable');
    });

    beforeEach(async () => {
        Token = await TokenFactory.deploy("GaugeToken", "GaugeToken");
        GaugeController = await GaugeControllerFactory.deploy(
            Token.address,
            "0x0000000000000000000000000000000000000000",
        );
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
            await Token.mint(wallet1.address, utils.parseEther('100'));
            await Token.approve(GaugeController.address, utils.parseEther('100'));
            const tx = await GaugeController.deposit(wallet1.address, utils.parseEther('100'))
            expect(tx.confirmations).to.be.equal(1);
        });
    })

    /**
     * @description Test withdraw(uint256 _amount) function
     * Expected Behavior:
     * 1. decrease `balance` of `msg.sender` address
     * 1. transfer `token` from `address(this)` to `msg.sender`
     * 3. emit a Withdraw event
     */
     describe('withdraw(uint256 _amount)', () => {
        it('should SUCCEED to withdraw funds', async () => {
            await Token.mint(wallet1.address, utils.parseEther('100'));
            await Token.approve(GaugeController.address, utils.parseEther('100'));
            await GaugeController.deposit(wallet1.address, utils.parseEther('100'))
            const tx = await GaugeController.withdraw(utils.parseEther('100'))
            expect(tx.confirmations).to.be.equal(1);
        });
    })

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
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000001")).to.eq("0")
            await Token.mint(wallet1.address, utils.parseEther('100'));
            await Token.approve(GaugeController.address, utils.parseEther('100'));
            await GaugeController.deposit(wallet1.address, utils.parseEther('100'))
            const tx = await GaugeController.increaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('100'))
            expect(tx.confirmations).to.be.equal(1);
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000001")).to.eq("100000000000000000000")
        });
        it('should FAIL to increase gaugeBalance BECAUSE of insufficient balance', async () => {
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            expect(GaugeController.increaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('100'))).to.be.reverted
        });
    })

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
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000001")).to.eq("0")
            await Token.mint(wallet1.address, utils.parseEther('200'));
            await Token.approve(GaugeController.address, utils.parseEther('200'));
            await GaugeController.deposit(wallet1.address, utils.parseEther('200'))
            await GaugeController.increaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('200'))
            const tx = await GaugeController.decreaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('100'))
            expect(tx.confirmations).to.be.equal(1);
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000001")).to.eq("100000000000000000000")
        });
        it('should FAIL to increase staked balance BECAUSE of insufficient gaugeBalance.', async () => {
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            expect(GaugeController.decreaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('100'))).to.be.reverted
        });
    })

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
            await GaugeController.addGaugeWithScale("0x0000000000000000000000000000000000000001", utils.parseEther('1'))
            expect(await GaugeController.getGaugeScale("0x0000000000000000000000000000000000000001")).to.eq("1000000000000000000")
        });
    })

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
            await GaugeController.removeGauge("0x0000000000000000000000000000000000000001")
            expect(await GaugeController.getGaugeScale("0x0000000000000000000000000000000000000001")).to.eq("0")
        });
    })

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
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            await GaugeController.setGaugeScale("0x0000000000000000000000000000000000000001", utils.parseEther('2'))
            expect(await GaugeController.getGaugeScale("0x0000000000000000000000000000000000000001")).to.eq("2000000000000000000")
        });
        
        it('should SUCCEED to DECREASE the scale on EXISTING gauge', async () => {
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            await GaugeController.setGaugeScale("0x0000000000000000000000000000000000000001", utils.parseEther('0.5'))
            expect(await GaugeController.getGaugeScale("0x0000000000000000000000000000000000000001")).to.eq("500000000000000000")
        });
    })

    /**
     * @description Test getGauge(address _gauge) function
     * -= Expected Behavior =-
     * 1. read `GaugeTwabs.details.balance`
     */
     describe('getGauge(address _gauge)', () => {
        it('should SUCCEED to READ the GaugeTwabs[gauge].details.balance from EMPTY mapping', async () => {
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000002")).to.eq("0")
        });

        it('should SUCCEED to READ the GaugeTwabs[gauge].details.balance from INITIALIZED mapping', async () => {
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000001")).to.eq("0")
        });
    })
    
    /**
     * @description Test getGaugeScale(address _gauge) function
     * -= Expected Behavior =-
     * 1. read `GaugeScaleTwabs.details.balance`
     */
     describe('getGaugeScale(address _gauge)', () => {
        it('should SUCCEED to READ the GaugeScaleTwabs[gauge].details.balance from EMPTY mapping', async () => {
            expect(await GaugeController.getGauge("0x0000000000000000000000000000000000000002")).to.eq("0")
        });

        it('should SUCCEED to READ the GaugeScaleTwabs[gauge].details.balance from INITIALIZED mapping', async () => {
            await GaugeController.addGauge("0x0000000000000000000000000000000000000001");
            expect(await GaugeController.getGaugeScale("0x0000000000000000000000000000000000000001")).to.eq("1000000000000000000")
        });
    })

    /**
     * @description Test getScaledAverageGaugeBetween(address _gauge, uint256 _startTime, uint256 _endTime) function
     * -= Expected Behavior =-
     * 1. read `Gauge` average balance between `_startTime` and `_endTime`
     * 2. read `GaugeScale` average balance between `_startTime` and `_endTime` 
     * 3. compute average of `Gauge` and `GaugeScale`
     */
     describe('getScaledAverageGaugeBetween(address _gauge, uint256 _startTime, uint256 _endTime)', () => {
        it('should SUCCEED to READ the scaled average of', async () => {
            // Add Gauge with Scale TWAB
            await GaugeController.addGaugeWithScale("0x0000000000000000000000000000000000000001", utils.parseEther('1'));

            // Increase Gauge TWAB
            await Token.mint(wallet1.address, utils.parseEther('100'));
            await Token.approve(GaugeController.address, utils.parseEther('100'));
            await GaugeController.deposit(wallet1.address, utils.parseEther('100'))
            await GaugeController.increaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('100'))
            
            // Simulate Increase in Time by 1 Day (86400 seconds)
            await increaseTime(ethers.provider, 86400)
            const timestamp = (await ethers.provider.getBlock('latest')).timestamp
            const startTime = timestamp - 86400
            const endTime = timestamp

            // READ Scaled Gauge TWAB
            const read =  await GaugeController.getScaledAverageGaugeBetween("0x0000000000000000000000000000000000000001", startTime, endTime)
            expect(read).to.eq("100000000000000000000")
        });
    })

    /**
     * @description Test getAverageGaugeBetween(address _gauge, uint256 _startTime, uint256 _endTime) function
     * -= Expected Behavior =-
     * 1. read `Gauge` average balance between `_startTime` and `_endTime`
     */
     describe('getAverageGaugeBetween(address _gauge, uint256 _startTime, uint256 _endTime)', () => {
        it('should SUCCEED to READ the balance average of the gauge', async () => {
            // Add Gauge with Scale TWAB
            await GaugeController.addGaugeWithScale("0x0000000000000000000000000000000000000001", utils.parseEther('1'));

            // Increase Gauge TWAB
            await Token.mint(wallet1.address, utils.parseEther('100'));
            await Token.approve(GaugeController.address, utils.parseEther('100'));
            await GaugeController.deposit(wallet1.address, utils.parseEther('100'))
            await GaugeController.increaseGauge("0x0000000000000000000000000000000000000001", utils.parseEther('100'))
            
            // Simulate Increase in Time by 1 Day (86400 seconds)
            await increaseTime(ethers.provider, 86400)
            const timestamp = (await ethers.provider.getBlock('latest')).timestamp
            const startTime = timestamp - 86400
            const endTime = timestamp

            // READ Gauge TWAB
            const read =  await GaugeController.getAverageGaugeBetween("0x0000000000000000000000000000000000000001", startTime, endTime)
            expect(read).to.eq("100000000000000000000")
        });
    })
    
    /**
     * @description Test getAverageGaugeScaleBetween(address _gauge, uint256 _startTime, uint256 _endTime) function
     * -= Expected Behavior =-
     * 1. read `GaugeScale` average balance between `_startTime` and `_endTime`
     */
     describe('getAverageGaugeScaleBetween(address _gauge, uint256 _startTime, uint256 _endTime)', () => {
        it('should SUCCEED to READ the scale TWAB of the gauge', async () => {
            // Add Gauge with Scale TWAB
            await GaugeController.addGaugeWithScale("0x0000000000000000000000000000000000000001", utils.parseEther('1'));
            
            // Simulate Increase in Time by 1 Day (86400 seconds)
            await increaseTime(ethers.provider, 86400)
            const timestamp = (await ethers.provider.getBlock('latest')).timestamp
            const startTime = timestamp - 86400
            const endTime = timestamp

            // READ Gauge TWAB
            const read =  await GaugeController.getAverageGaugeScaleBetween("0x0000000000000000000000000000000000000001", startTime, endTime)
            expect(read).to.eq("1000000000000000000")
        });
    })
    
   
});
