import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { ethers, artifacts } from 'hardhat';
import { Signer } from '@ethersproject/abstract-signer';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, Contract, ContractFactory } from 'ethers';
import { Draw, TsunamiDrawCalculatorSettings } from './types';

const { getSigners } = ethers;
const newDebug = require('debug')

describe('OracleTimelock', () => {
  let wallet1: SignerWithAddress;
  let wallet2: SignerWithAddress;

  let oracleTimelock: Contract

  let tsunamiDrawSettingsHistory: MockContract
  let drawHistory: MockContract
  let drawCalculator: MockContract

  let oracleTimelockFactory: ContractFactory

  const timelockDuration = 60

  beforeEach(async () => {
    [wallet1, wallet2] = await getSigners();

    const TsunamiDrawSettingsHistory = await artifacts.readArtifact('TsunamiDrawSettingsHistory');
    tsunamiDrawSettingsHistory = await deployMockContract(wallet1 as Signer, TsunamiDrawSettingsHistory.abi)

    const DrawHistory = await artifacts.readArtifact('DrawHistory');
    drawHistory = await deployMockContract(wallet1 as Signer, DrawHistory.abi)

    const IDrawCalculator = await artifacts.readArtifact('IDrawCalculator');
    drawCalculator = await deployMockContract(wallet1 as Signer, IDrawCalculator.abi)

    oracleTimelockFactory = await ethers.getContractFactory('OracleTimelock');

    oracleTimelock = await oracleTimelockFactory.deploy(
      wallet1.address,
      tsunamiDrawSettingsHistory.address,
      drawHistory.address,
      drawCalculator.address,
      timelockDuration
    )
  });

  describe('constructor()', () => {
    it('should set the drawHistory', async () => {
      expect(await oracleTimelock.getDrawHistory()).to.equal(drawHistory.address)
    })

    it('should set the draw calculator', async () => {
      expect(await oracleTimelock.getDrawCalculator()).to.equal(drawCalculator.address)
    })

    it('should set the tsunami draw settings history', async () => {
      expect(await oracleTimelock.getTsunamiDrawSettingsHistory()).to.equal(tsunamiDrawSettingsHistory.address)
    })
  })

  describe('getTimelockDuration()', () => {
    it('should return the duration', async () => {
      expect(await oracleTimelock.getTimelockDuration()).to.equal(timelockDuration)
    })
  })

  describe('setTimelockDuration()', () => {
    it('should set the duration', async () => {
      await oracleTimelock.setTimelockDuration(77)
      expect(await oracleTimelock.getTimelockDuration()).to.equal(77)
    })

    it('should not allow anyone else to set', async () => {
      await expect(oracleTimelock.connect(wallet2).setTimelockDuration(66)).to.be.revertedWith('Ownable/caller-not-owner')
    })
  })

  describe('setTimelock()', () => {
    it('should allow the owner to force the timelock', async () => {
      const timestamp = 523
      await oracleTimelock.setTimelock({
        drawId: 1,
        timestamp
      })

      const timelock = await oracleTimelock.getTimelock()
      expect(timelock.drawId).to.equal(1)
      expect(timelock.timestamp).to.equal(timestamp)
    })
  })

  describe('calculate()', () => {
    it('should do nothing if no timelock is set', async () => {
      await drawCalculator.mock.calculate.withArgs(wallet1.address, [0], '0x').returns([43])
      const result = await oracleTimelock.calculate(wallet1.address, [0], '0x')
      expect(result[0]).to.equal('43')
    })

    context('with timelock draw', () => {
      let timestamp: number

      beforeEach(async () => {
        timestamp = (await ethers.provider.getBlock('latest')).timestamp
        await oracleTimelock.setTimelock({
          drawId: 1,
          timestamp: timestamp + 1000
        })
      })

      it('should revert if the timelock is set for the draw', async () => {
        await expect(oracleTimelock.calculate(wallet1.address, [1], '0x')).to.be.revertedWith('OM/timelock-not-expired')
      })

      it('should pass for draws that are not locked', async () => {
        await drawCalculator.mock.calculate.withArgs(wallet1.address, [0, 2], '0x').returns([44, 5])
        const result = await oracleTimelock.calculate(wallet1.address, [0, 2], '0x')
        expect(result[0]).to.equal('44')
        expect(result[1]).to.equal('5')
      })
    })
  })

  describe('push()', () => {
    const debug = newDebug('pt:OracleTimelock.test.ts:push()')

    const draw: Draw = {
      drawId: BigNumber.from(0),
      winningRandomNumber: BigNumber.from(1),
      timestamp: BigNumber.from(10)
    }

    const drawSettings: TsunamiDrawCalculatorSettings = {
      matchCardinality: BigNumber.from(5),
      numberOfPicks: ethers.utils.parseEther('1'),
      distributions: [ethers.utils.parseUnits('0.5', 9)],
      bitRangeSize: BigNumber.from(3),
      prize: ethers.utils.parseEther('100'),
      drawStartTimestampOffset: BigNumber.from(0),
      drawEndTimestampOffset: BigNumber.from(3600),
      maxPicksPerUser: BigNumber.from(10)
    }

    it('should allow a push when no push has happened', async () => {
      await drawHistory.mock.pushDraw.returns(draw.drawId)
      await tsunamiDrawSettingsHistory.mock.pushDrawSettings.returns(true)
      const tx = await oracleTimelock.push(draw, drawSettings)
      const block = await ethers.provider.getBlock(tx.blockNumber)

      const timelock = await oracleTimelock.getTimelock()
      expect(timelock.drawId).to.equal(draw.drawId)
      expect(timelock.timestamp).to.equal(block.timestamp)
    })

    it('should not allow a push from a non-owner', async () => {
      await expect(oracleTimelock.connect(wallet2).push(draw, drawSettings)).to.be.revertedWith('Manageable/caller-not-manager-or-owner')
    })

    it('should not allow a push if a draw is still timelocked', async () => {
      await drawHistory.mock.pushDraw.returns(draw.drawId)
      await tsunamiDrawSettingsHistory.mock.pushDrawSettings.returns(true)
      await oracleTimelock.push(draw, drawSettings)

      await expect(oracleTimelock.push(draw, drawSettings)).to.be.revertedWith('OM/timelock-not-expired')
    })
  })
})
