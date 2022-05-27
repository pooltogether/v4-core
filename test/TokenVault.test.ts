import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const { constants, getContractFactory, getSigners, utils } = ethers;
const { AddressZero, Zero } = constants;
const { parseEther: toWei } = utils;

describe('Vault', () => {
    let TokenVaultFactory: ContractFactory;
    let tokenVault: Contract;
    let token: Contract;

    let owner: SignerWithAddress;
    let manager: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let wallet4: SignerWithAddress;

    let constructorTest = false;

    beforeEach(async () => {
        [owner, manager, wallet3, wallet4] = await getSigners();

        const ERC20MintableContract = await getContractFactory('ERC20Mintable', owner);
        token = await ERC20MintableContract.deploy('PoolTogether', 'POOL');

        TokenVaultFactory = await getContractFactory('TokenVault', owner);

        if (!constructorTest) {
            tokenVault = await TokenVaultFactory.deploy(owner.address);
        }
    });

    describe('constructor', () => {
        beforeEach(() => {
            constructorTest = true;
        });

        afterEach(() => {
            constructorTest = false;
        });

        it('should set the owner', async () => {
            tokenVault = await TokenVaultFactory.deploy(owner.address);
            expect(await tokenVault.owner()).to.equal(owner.address);
        });

        it('should fail if owner is address zero', async () => {
            await expect(TokenVaultFactory.deploy(AddressZero)).to.be.revertedWith(
                'TVault/owner-not-zero-address',
            );
        });
    });

    describe('setApproval()', () => {
        it('should allow the owner to approve accounts', async () => {
            await expect(tokenVault.setApproval(wallet3.address, true))
                .to.emit(tokenVault, 'Approved')
                .withArgs(wallet3.address, true);

            expect(await tokenVault.approved(wallet3.address)).to.equal(true);
        });

        it('should fail if not owner', async () => {
            await expect(
                tokenVault.connect(manager).setApproval(wallet3.address, true),
            ).to.be.revertedWith('Ownable/caller-not-owner');
        });
    });

    describe('increaseERC20Allowance()', () => {
        let increaseAllowanceAmount: BigNumber;

        beforeEach(async () => {
            increaseAllowanceAmount = toWei('1111');
        });

        it('should allow owner to increase approval amount', async () => {
            await tokenVault.setApproval(wallet3.address, true);
            await tokenVault.increaseERC20Allowance(
                token.address,
                wallet3.address,
                increaseAllowanceAmount,
            );

            expect(await token.allowance(tokenVault.address, wallet3.address)).to.equal(
                increaseAllowanceAmount,
            );
        });

        it('should allow manager to increase approval amount', async () => {
            await tokenVault.setApproval(wallet3.address, true);
            await tokenVault.setManager(manager.address);

            await tokenVault
                .connect(manager)
                .increaseERC20Allowance(token.address, wallet3.address, increaseAllowanceAmount);

            expect(await token.allowance(tokenVault.address, wallet3.address)).to.equal(
                increaseAllowanceAmount,
            );
        });

        it('should fail if spender is not approved', async () => {
            await expect(
                tokenVault.increaseERC20Allowance(
                    token.address,
                    wallet3.address,
                    increaseAllowanceAmount,
                ),
            ).to.be.revertedWith('TVault/spender-not-approved');
        });

        it('should fail if not owner or manager', async () => {
            await tokenVault.setManager(wallet3.address);

            await expect(
                tokenVault
                    .connect(wallet4)
                    .increaseERC20Allowance(
                        token.address,
                        manager.address,
                        increaseAllowanceAmount,
                    ),
            ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });
    });

    describe('decreaseERC20Allowance()', () => {
        let decreaseAllowanceAmount: BigNumber;
        let increaseAllowanceAmount: BigNumber;

        beforeEach(async () => {
            decreaseAllowanceAmount = toWei('111');
            increaseAllowanceAmount = toWei('1111');

            await tokenVault.setApproval(wallet3.address, true);
            await tokenVault.increaseERC20Allowance(
                token.address,
                wallet3.address,
                increaseAllowanceAmount,
            );
        });

        it('should allow owner to decrease approval amount', async () => {
            await tokenVault.decreaseERC20Allowance(
                token.address,
                wallet3.address,
                decreaseAllowanceAmount,
            );

            expect(await token.allowance(tokenVault.address, wallet3.address)).to.equal(
                increaseAllowanceAmount.sub(decreaseAllowanceAmount),
            );
        });

        it('should allow owner to decrease approval amount', async () => {
            await tokenVault.setManager(manager.address);

            await tokenVault
                .connect(manager)
                .decreaseERC20Allowance(token.address, wallet3.address, decreaseAllowanceAmount);

            expect(await token.allowance(tokenVault.address, wallet3.address)).to.equal(
                increaseAllowanceAmount.sub(decreaseAllowanceAmount),
            );
        });

        it('should decrease the full approval amount', async () => {
            await tokenVault.decreaseERC20Allowance(
                token.address,
                wallet3.address,
                increaseAllowanceAmount,
            );

            expect(await token.allowance(tokenVault.address, wallet3.address)).to.equal(Zero);
        });

        it('should fail if not owner of manager', async () => {
            await expect(
                tokenVault
                    .connect(wallet4)
                    .decreaseERC20Allowance(
                        token.address,
                        wallet3.address,
                        decreaseAllowanceAmount,
                    ),
            ).to.be.revertedWith('Manageable/caller-not-manager-or-owner');
        });
    });
});
