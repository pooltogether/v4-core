import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { utils, Contract, ContractFactory, Signer, Wallet } from 'ethers';
import { ethers, artifacts } from 'hardhat';
import { Interface } from 'ethers/lib/utils';

const { getSigners, provider } = ethers;
const { parseEther: toWei } = utils;

const increaseTime = async (time: number) => {
    await provider.send('evm_increaseTime', [ time ]);
    await provider.send('evm_mine', []);
};

function printBalances(balances: any) {
    balances = balances.filter((balance: any) => balance.timestamp != 0)
    balances.map((balance: any) => {
        console.log(`Balance @ ${balance.timestamp}: ${ethers.utils.formatEther(balance.balance)}`)
    })
}

describe('WaveModel', () => {
    let waveModel: Contract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    
    let draw: any
    const encoder = ethers.utils.defaultAbiCoder

    beforeEach(async () =>{
        [ wallet1, wallet2, wallet3 ] = await getSigners();
        const waveModelFactory = await ethers.getContractFactory("WaveModel")
        waveModel = await waveModelFactory.deploy()

        await waveModel.setMatchCardinality(5)
        await waveModel.setPrizeDistribution([ethers.utils.parseEther("0.2"), ethers.utils.parseEther("0.8")])

    })

    describe('calculate()', () => {
      it.only('should calculate', async () => {
        //uint256 randomNumber, uint256 prize, uint256 totalSupply, uint256 balance, bytes32 userRandomNumber, uint256[] calldata picks)

        // await expect(waveModel.calculate())
      })
    });
})
