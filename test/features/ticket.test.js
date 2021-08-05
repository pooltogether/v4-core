const { PoolEnv } = require('./support/PoolEnv')

describe('Tickets Feature', () => {

  let env

  beforeEach(() => {
    env = new PoolEnv()
  })

  it('should be possible to purchase tickets', async () => {
    await env.createPool({ prizePeriodSeconds: 10, creditLimit: '0.1', creditRate: '0.01' })
    await env.buyTickets({ user: 1, tickets: 100 })
    await env.buyTickets({ user: 2, tickets: 50 })
    await env.expectUserToHaveTickets({ user: 1, tickets: 100 })
    await env.expectUserToHaveTickets({ user: 2, tickets: 50 })
  })

  it('should be possible to win tickets', async () => {

  })

  it('should account for reserve fees when awarding prizes', async () => {

  })

  it('should not be possible to buy or transfer tickets during award', async () => {

  })

})