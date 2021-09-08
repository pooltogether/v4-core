const { PoolEnv } = require('./support/PoolEnv');
const ethers = require('ethers')

const toWei = (val) => ethers.utils.parseEther('' + val);

describe('Oracle jobs', () => {
  let env;

  beforeEach(async () => {
    env = new PoolEnv()
    await env.ready()
  });

  it('should be able to trigger the beacon', async () => {
    await env.draw({ randomNumber: 1 })
    await env.expectDrawRandomNumber({ drawId: 0, randomNumber: 1 })
  });

  it('should be able to push new draw settings', async () => {
    await env.poolAccrues({ tickets: 10 })
    await env.draw({ randomNumber: 1 })
    bitRangeSize = 2
    matchCardinality = 2
    pickCost = toWei(1)
    distributions = [toWei(1)]
    prize = toWei(10)
    await env.setDrawSettings({
      drawId: 0,
      bitRangeSize,
      matchCardinality,
      pickCost,
      distributions,
      prize
    })
  })

});
