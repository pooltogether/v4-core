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

function printBalances(drawCalculators: any) {
    drawCalculators = drawCalculators.filter((balance: any) => balance.timestamp != 0)
    drawCalculators.map((balance: any) => {
        console.log(`Balance @ ${balance.timestamp}: ${ethers.utils.formatEther(balance.balance)}`)
    })
}

describe('Strategy', () => {
    let claimableDraw: Contract;
    let wallet1: any;
    let wallet2: any;
    let wallet3: any;

    let drawCalculator: MockContract;
    let draw: any
    const encoder = ethers.utils.defaultAbiCoder

    beforeEach(async () =>{
        [ wallet1, wallet2, wallet3 ] = await getSigners();

        let IDrawCalculator = await artifacts.readArtifact('IDrawCalculator')
        drawCalculator = await deployMockContract(wallet1, IDrawCalculator.abi)

        const claimableDrawFactory: ContractFactory = await ethers.getContractFactory("ClaimableDrawHarness");
        claimableDraw = await claimableDrawFactory.deploy();

        draw = {
          randomNumber: 1,
          timestamp: 0,
          prize: 10000,
        }

        await claimableDraw.setDrawCalculator(drawCalculator.address)
        await claimableDraw.createDraw(draw.randomNumber, draw.timestamp, draw.prize)
      })
    
      // const userRandomNumber =  utils.solidityKeccak256(['address'], [wallet1.address])

    describe('claim()', () => {
      it('should claim', async () => {
        const user = wallet1.address;
        const drawIds = [[0]];
        const drawCalculators = [drawCalculator.address]
        const prizes = [toWei("1")]

        // totalPayout += drawCalculator.calculate(user, randomNumbers, timestamps, prizes, data);
        await drawCalculator.mock.calculate.withArgs(user, [1], [0], [10000], '0x')
          .returns(toWei("11"))

        await claimableDraw.claimIt(user, drawIds, drawCalculators, '0x')

        expect(await claimableDraw.hasClaimed(wallet1.address, 0)).to.equal(true)
      })
    });
})
