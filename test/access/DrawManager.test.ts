import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const {
    constants: { AddressZero },
    getSigners,
} = ethers;

describe('drawManager()', () => {
    let contractOwner: any;
    let drawManager: any;
    let drawManagerContract: Contract;

    before(async () => {
        [contractOwner, drawManager] = await getSigners();

        const drawManagerFactory: ContractFactory = await ethers.getContractFactory(
            'DrawManagerHarness',
        );

        drawManagerContract = await drawManagerFactory.deploy();
    });

    it.only('should setDrawManager', async () => {
        await expect(
            drawManagerContract.connect(contractOwner).setDrawManager(drawManager.address),
        )
            .to.emit(drawManagerContract, 'DrawManagerTransferred')
            .withArgs(AddressZero, drawManager.address);

        expect(await drawManagerContract.drawManager()).to.equal(drawManager.address);
    });

    it.only('should fail to setDrawManager', async () => {
        await expect(
            drawManagerContract.connect(contractOwner).setDrawManager(AddressZero),
        ).to.be.revertedWith('drawManager/drawManager-not-zero-address');
    });

    it.only('should fail to call permissionedCall function', async () => {
        await expect(
            drawManagerContract.connect(contractOwner).permissionedCall(),
        ).to.be.revertedWith('drawManager/caller-not-draw-manager');
    });

    it.only('should succeed to call permissionedCall function', async () => {
        expect(await drawManagerContract.connect(drawManager).callStatic.permissionedCall()).to.equal(
            'isDrawManager',
        );
    });
});
