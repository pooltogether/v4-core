import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { ethers } from 'hardhat';

const { getContractFactory, getSigners, utils } = ethers;
const { parseEther: toWei } = utils;

describe('TokenFaucet', () => {
    let faucet: Contract;
    let token: Contract;

    let owner: SignerWithAddress;
    let manager: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let wallet4: SignerWithAddress;

    beforeEach(async () => {
        [owner, manager, wallet3, wallet4] = await getSigners();

        const TokenFaucetContract = await getContractFactory('TokenFaucet', owner);
        faucet = await TokenFaucetContract.deploy();

        const ERC20MintableContract = await getContractFactory('ERC20Mintable', owner);
        token = await ERC20MintableContract.deploy('PoolTogether', 'POOL');
    });

    describe('drip', () => {
        it('should allow a user to claim 0.01% of all tokens', async () => {
            const amount = toWei('100');
            const dripAmount = toWei('0.01');

            await token.mint(faucet.address, amount);

            expect(await token.balanceOf(faucet.address)).to.equal(amount);

            await faucet.drip(token.address);

            expect(await token.balanceOf(faucet.address)).to.equal(amount.sub(dripAmount));
            expect(await token.balanceOf(owner.address)).to.equal(dripAmount);
        });

        it('should fail if faucet is empty', async () => {
            await expect(faucet.drip(token.address)).to.be.revertedWith(
                'TokenFaucet/empty-token-balance',
            );
        });
    });
});
