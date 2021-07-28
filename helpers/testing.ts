import { ethers } from 'hardhat';
const { provider } = ethers;

export const increaseTime = async (time: number) => {
  await provider.send('evm_increaseTime', [ time ]);
};

export const increaseTimeAndMine = async (time: number) => {
  await provider.send('evm_increaseTime', [ time ]);
  await provider.send('evm_mine', []);
};

export function printBalances(drawCalculators: any) {
  drawCalculators = drawCalculators.filter((balance: any) => balance.timestamp != 0)
  drawCalculators.map((balance: any) => {
      console.log(`Balance @ ${balance.timestamp}: ${ethers.utils.formatEther(balance.balance)}`)
  })
}
