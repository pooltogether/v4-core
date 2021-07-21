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

describe('Strategy', () => {
    let strategy: Contract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    let waveModel: MockContract;
    let draw: any
    const encoder = ethers.utils.defaultAbiCoder

    beforeEach(async () =>{
        [ wallet1, wallet2, wallet3 ] = await getSigners();

        let IWaveModel = await artifacts.readArtifact('IWaveModel')
        waveModel = await deployMockContract(wallet1, IWaveModel.abi)

        const strategyFactory: ContractFactory = await ethers.getContractFactory("StrategyHarness");
        strategy = await strategyFactory.deploy();
        await strategy.setWaveModel(waveModel.address);
        await strategy.setDrawId(waveModel.address);

        draw = {
          randomNumber: 1,
          timestamp: 0,
          totalSupply: 1000,
          prize: 10000,
        }
        await strategy.setDraw(draw)

    })

    describe('claim()', () => {
      it.only('should claim', async () => {
        const user = wallet1.address;
        const timestamps = [0];
        const balances = [toWei("2")]
        const userRandomNumber =  utils.solidityKeccak256(['address'], [wallet1.address])
        const pickIndices = encoder.encode(["uint256[][]"], [[["1"]]])
        await waveModel.mock.calculate.withArgs(draw.randomNumber, draw.prize, draw.totalSupply, toWei("2").toString(), userRandomNumber, ["1"])
          .returns(toWei("11"))

        await expect(strategy.claimIt(user, timestamps, balances, pickIndices))
          .to.emit(strategy, 'Claimed')
      })
    });
})
