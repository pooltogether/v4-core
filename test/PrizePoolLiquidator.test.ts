import { expect } from 'chai';
import { ethers } from 'hardhat';
import { constants, Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

const { getContractFactory, getSigners, utils } = ethers;
const { parseEther: toWei } = utils;

describe('Reserve', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let reserve: Contract;
    let ticket: Contract;
    let ReserveHarnessFactory: ContractFactory;
    let erc20MintableFactory: ContractFactory;

    before(async () => {
        [wallet1, wallet2, wallet3] = await getSigners();

        erc20MintableFactory = await getContractFactory('ERC20Mintable');
        ReserveHarnessFactory = await getContractFactory('ReserveHarness');
    });

    beforeEach(async () => {
        ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
        reserve = await ReserveHarnessFactory.deploy(wallet1.address, ticket.address);
    });

});
