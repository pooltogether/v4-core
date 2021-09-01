import { expect } from 'chai';
import { Contract, ContractFactory } from 'ethers';
import { ethers } from 'hardhat';

const {
    constants: { AddressZero },
    getSigners,
} = ethers;

describe('drawStrategist()', () => {
    let contractOwner: any;
    let drawStrategist: any;
    let drawStrategistContract: Contract;

    before(async () => {
        [contractOwner, drawStrategist] = await getSigners();

        const drawStrategistFactory: ContractFactory = await ethers.getContractFactory(
            'DrawStrategistHarness',
        );

        drawStrategistContract = await drawStrategistFactory.deploy();
    });

    it('should setDrawStrategist', async () => {
        await expect(drawStrategistContract.connect(contractOwner).setDrawStrategist(drawStrategist.address))
            .to.emit(drawStrategistContract, 'DrawStrategistTransferred')
            .withArgs(AddressZero, drawStrategist.address);

        expect(await drawStrategistContract.drawStrategist()).to.equal(drawStrategist.address);
    });

    it('should fail to setDrawStrategist', async () => {
        await expect(
            drawStrategistContract.connect(contractOwner).setDrawStrategist(AddressZero),
        ).to.be.revertedWith('DrawStrategist/drawStrategist-not-zero-address');
    });

    it('should fail to call permissionedCall function', async () => {
        await expect(
            drawStrategistContract.connect(contractOwner).permissionedCall(),
        ).to.be.revertedWith('DrawStrategist/caller-not-drawStrategist');
    });

    it('should succeed to call permissionedCall function', async () => {
        expect(
            await drawStrategistContract.connect(drawStrategist).callStatic.permissionedCall(),
        ).to.equal('isDrawStrategist');
    });
});
