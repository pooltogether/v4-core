import { expect } from 'chai';
import { ethers, artifacts } from 'hardhat';
import { constants, Contract, ContractFactory } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { deployMockContract } from 'ethereum-waffle';

const { getContractFactory, getSigners, utils } = ethers;
const { parseEther: toWei } = utils;

describe('PrizePoolLiquidator', () => {
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let wallet3: SignerWithAddress;
    let reserve: Contract;
    let ticket: Contract;
    let PrizePoolLiquidatorHarnessFactory: ContractFactory;
    let erc20MintableFactory: ContractFactory;

    let ppl: Contract;
    let pool: Contract;

    let IPrizePool: any;

    before(async () => {
        [wallet1, wallet2, wallet3] = await getSigners();

        erc20MintableFactory = await getContractFactory('ERC20Mintable');
        ticket = await erc20MintableFactory.deploy('Ticket', 'TICK');
        PrizePoolLiquidatorHarnessFactory = await getContractFactory('PrizePoolLiquidatorHarness');
        IPrizePool = await artifacts.readArtifact('IPrizePool')

    });
    
    beforeEach(async () => {
        ppl = await PrizePoolLiquidatorHarnessFactory.deploy()
        pool = await deployMockContract(wallet1, IPrizePool.abi)
    })

    describe('setPrizePool()', () => {
        it('should set the prize pool values', async () => {
            
        })
    })
});
