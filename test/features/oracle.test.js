const { PoolEnv } = require('./support/PoolEnv');
const ethers = require('ethers');

const toWei = (val) => ethers.utils.parseEther('' + val);

describe('Oracle jobs', () => {
  let env;

  beforeEach(async () => {
    env = new PoolEnv();
    await env.ready();
  });

  it('should be able to trigger the beacon', async () => {
    await env.draw({ randomNumber: 1 });
    await env.expectDrawRandomNumber({ drawId: 0, randomNumber: 1 });
  });

  it('should be able to push new draw settings', async () => {
    await env.poolAccrues({ tickets: 10 });
    await env.draw({ randomNumber: 1 });
    bitRangeSize = 2;
    matchCardinality = 2;
    numberOfPicks = toWei(1);
    distributions = [ethers.utils.parseUnits('1', 9)];
    prize = toWei(10);
    drawStartTimestampOffset = 1;
    drawEndTimestampOffset = 2;
    maxPicksPerUser = 1000;

    await env.pushDrawSettings({
      drawId: 1,
      bitRangeSize,
      matchCardinality,
      drawStartTimestampOffset,
      drawEndTimestampOffset,
      numberOfPicks,
      distributions,
      prize,
      maxPicksPerUser,
    });
  });
});
