import { expect } from 'chai';
import { ethers, artifacts } from 'hardhat';
import { Contract, ContractFactory } from 'ethers';
import { Signer } from '@ethersproject/abstract-signer';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
const { getSigners } = ethers;
const { parseEther: toWei } = ethers.utils;

describe('PrizeFlush', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;

    // Contracts
    let prizeFlush: Contract;
    let reserve: Contract;
    let ticket: Contract;
    let strategy: MockContract;
    let prizeFlushFactory: ContractFactory;
    let reserveFactory: ContractFactory;
    let erc20MintableFactory: ContractFactory;
    let prizeSplitStrategyFactory: ContractFactory;

    let DESTINATION: any;

    before(async () => {
        [wallet1, wallet2, wallet3] = await getSigners();
        DESTINATION = wallet3.address;
        erc20MintableFactory = await ethers.getContractFactory('ERC20Mintable');
        prizeFlushFactory = await ethers.getContractFactory('PrizeFlush');
        reserveFactory = await ethers.getContractFactory('ReserveHarness');
        prizeSplitStrategyFactory = await ethers.getContractFactory('PrizeSplitStrategy');

        let PrizeSplitStrategy = await artifacts.readArtifact('PrizeSplitStrategy');
        strategy = await deployMockContract(wallet1 as Signer, PrizeSplitStrategy.abi);
    });

    beforeEach(async () => {
        ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
        reserve = await reserveFactory.deploy(wallet1.address, ticket.address);

        prizeFlush = await prizeFlushFactory.deploy(
            wallet1.address,
            DESTINATION,
            strategy.address,
            reserve.address,
        );

        await reserve.setManager(prizeFlush.address);
    });

    describe('Getters', () => {
        it('should get the destination address', async () => {
            expect(await prizeFlush.getDestination()).to.equal(DESTINATION);
        });

        it('should get the strategy address', async () => {
            expect(await prizeFlush.getStrategy()).to.equal(strategy.address);
        });

        it('should get the reserve address', async () => {
            expect(await prizeFlush.getReserve()).to.equal(reserve.address);
        });
    });

    describe('Setters', () => {
        it('should fail to set the destination address', async () => {
            await expect(
                prizeFlush.connect(wallet3).setDestination(wallet3.address),
            ).to.revertedWith('Ownable/caller-not-owner');
        });

        it('should set the destination address', async () => {
            await expect(prizeFlush.setDestination(wallet3.address)).to.emit(
                prizeFlush,
                'DestinationSet',
            );
        });

        it('should fail to set the strategy address', async () => {
            await expect(prizeFlush.connect(wallet3).setStrategy(wallet3.address)).to.revertedWith(
                'Ownable/caller-not-owner',
            );
        });

        it('should set the strategy address', async () => {
            await expect(prizeFlush.setStrategy(wallet3.address)).to.emit(
                prizeFlush,
                'StrategySet',
            );
        });

        it('should fail to set the reserve address', async () => {
            await expect(prizeFlush.connect(wallet3).setReserve(wallet3.address)).to.revertedWith(
                'Ownable/caller-not-owner',
            );
        });

        it('should set the reserve address', async () => {
            await strategy.mock.distribute.returns(toWei('0'));
            await expect(prizeFlush.setReserve(wallet3.address)).to.emit(prizeFlush, 'ReserveSet');
        });
    });

    describe('Core', () => {
        describe('flush()', () => {
            it('should fail to call withdrawTo if zero balance on reserve', async () => {
                await strategy.mock.distribute.returns(toWei('0'));
                await expect(prizeFlush.flush()).to.not.emit(prizeFlush, 'Flushed');
            });

            it('should succeed to call withdrawTo prizes if positive balance on reserve.', async () => {
                await strategy.mock.distribute.returns(toWei('100'));
                await ticket.mint(reserve.address, toWei('100'));

                await expect(prizeFlush.flush())
                    .to.emit(prizeFlush, 'Flushed')
                    .and.to.emit(reserve, 'Withdrawn');
            });
        });
    });
});
