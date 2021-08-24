import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const {
    constants: { AddressZero },
    getSigners,
} = ethers;

describe('assetManager()', () => {
    let contractOwner: any;
    let assetManager: any;
    let assetManagerContract: Contract;

    before(async () => {
        [contractOwner, assetManager] = await getSigners();

        const assetManagerFactory: ContractFactory = await ethers.getContractFactory(
            'AssetManagerHarness',
        );

        assetManagerContract = await assetManagerFactory.deploy();
    });

    it('should setAssetManager', async () => {
        await expect(
            assetManagerContract.connect(contractOwner).setAssetManager(assetManager.address),
        )
            .to.emit(assetManagerContract, 'AssetManagerTransferred')
            .withArgs(AddressZero, assetManager.address);

        expect(await assetManagerContract.assetManager()).to.equal(assetManager.address);
    });

    it('should fail to setAssetManager', async () => {
        await expect(
            assetManagerContract.connect(contractOwner).setAssetManager(AddressZero),
        ).to.be.revertedWith('AssetManager/assetManager-not-zero-address');
    });

    it('should fail to call permissionedCall function', async () => {
        await expect(
            assetManagerContract.connect(contractOwner).permissionedCall(),
        ).to.be.revertedWith('AssetManager/caller-not-asset-manager');
    });

    it('should succeed to call permissionedCall function', async () => {
        expect(
            await assetManagerContract.connect(assetManager).callStatic.permissionedCall(),
        ).to.equal('isAssetManager');
    });
});
