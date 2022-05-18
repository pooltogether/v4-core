import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { deployMockContract } from 'ethereum-waffle';
import { Contract, Signer } from 'ethers';
import { ethers, artifacts } from 'hardhat';

const newDebug = require('debug');

const debug = newDebug('pt:Vault.test.ts');

const { getSigners } = ethers;

describe('Vault', () => {
    let vault: Contract;
    let token: Contract;

    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let wallet4: SignerWithAddress;

    beforeEach(async () => {
        [wallet1, wallet2, wallet3, wallet4] = await getSigners();

        const IERC20Artifact = await artifacts.readArtifact('IERC20');
        token = await deployMockContract(wallet1 as Signer, IERC20Artifact.abi);

        const VaultFactory = await ethers.getContractFactory('Vault', wallet1);
        vault = await VaultFactory.deploy(wallet1.address);
    });

    describe('constructor', () => {
        it('should set the owner', async () => {
            expect(await vault.owner()).to.equal(wallet1.address)
        })
    })

    describe('setApproval()', () => {
        it('should allow the owner to approve accounts', async () => {
            await vault.setApproved(wallet2.address, true)
            expect(await vault.approved(wallet2.address)).to.equal(true)
        })
    })

    describe('increaseERC20Allowance()', () => {
        it('should allow owners to increase approval amount', async () => {
            await vault.setApproved(wallet2.address, true)
            await token.mock.allowance.withArgs(vault.address, wallet2.address).returns('0')
            await token.mock.approve.withArgs(wallet2.address, '1111').returns(true)
            await vault.increaseERC20Allowance(token.address, wallet2.address, '1111')
        })

        it('should allow managers to increase approval amount', async () => {
            await vault.setManager(wallet3.address)
            await vault.setApproved(wallet2.address, true)
            await token.mock.allowance.withArgs(vault.address, wallet2.address).returns('0')
            await token.mock.approve.withArgs(wallet2.address, '1111').returns(true)
            await vault.connect(wallet3).increaseERC20Allowance(token.address, wallet2.address, '1111')
        })
    })

    describe('decreaseERC20Allowance()', () => {
        it('should allow manager to decrease approval amount', async () => {
            await token.mock.allowance.withArgs(vault.address, wallet2.address).returns('1111')
            await token.mock.approve.withArgs(wallet2.address, '111').returns(true)
            await vault.decreaseERC20Allowance(token.address, wallet2.address, '1000')
        })

        it('should allow manager to decrease approval amount', async () => {
            await vault.setManager(wallet3.address)
            await token.mock.allowance.withArgs(vault.address, wallet2.address).returns('1111')
            await token.mock.approve.withArgs(wallet2.address, '0').returns(true)
            await vault.connect(wallet3).decreaseERC20Allowance(token.address, wallet2.address, '1111')
        })
    })
});
