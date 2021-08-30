import hre from 'hardhat';
import { deploy1820 } from 'deploy-eip-1820';
import { Contract, ContractFactory } from 'ethers';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { expect } from 'chai';

import { setTime } from './helpers/increaseTime'

const now = () => (new Date().getTime() / 1000) | 0;

describe('DrawHistory', () => {
  let wallet1: any;
  let wallet2: any;
  let wallet3: any;
  let drawBeacon: Contract;
  let rng: MockContract;
  let registry: any

  let prizePeriodStart = now();
  let prizePeriodSeconds = 1000;

  before(async () => {
    [wallet1, wallet2, wallet3] = await hre.ethers.getSigners();
    registry = await deploy1820(wallet1);
  });

  beforeEach(async () => {
    const DrawBeaconHarnessFactory: ContractFactory = await hre.ethers.getContractFactory(
      'DrawBeaconHarness',
    );

    const RNGInterface = await hre.artifacts.readArtifact('RNGInterface');
    rng = await deployMockContract(wallet1, RNGInterface.abi);

    drawBeacon = await DrawBeaconHarnessFactory.deploy();
    await drawBeacon.initializeDrawBeacon(
      wallet1.address,
      prizePeriodStart,
      prizePeriodSeconds,
      rng.address
    );
  });

  describe('_saveRNGRequestWithDraw()', () => {
    it('should succeed to create a new using supplied random number and current block timestamp', async () => {
      setTime(hre.ethers.provider, 1756581197)
      await expect(
        await drawBeacon.saveRNGRequestWithDraw(
          1234567890,
        ),
      )
        .to.emit(drawBeacon, 'DrawCreated')
        .withArgs(
          0,
          0,
          1756581197,
          1234567890,
        );
    });
  });
});
