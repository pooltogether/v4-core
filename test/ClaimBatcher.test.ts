import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Contract, ContractFactory, Signer } from 'ethers';
import { ethers } from 'hardhat';
import { Interface } from 'ethers/lib/utils';

describe('Test Set Name', () => {
    let exampleContract: Contract

    beforeEach(async () =>{
        const exampleContractFactory: ContractFactory = await ethers.getContractFactory("ExampleContract")
        exampleContract = await exampleContractFactory.deploy()
    })

    it('Test Name', async () => {
        
    })

})