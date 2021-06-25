# Ticket Implementation

(a.k.a. Pick History)

- A user can prove they held a balance at a certain time
- A user can prove they held a balance over a duration of time

We can accomplish this using a time-weighted average balance.

Each time a token is transferred, we add to their previous TWAB.

New twab = last twab (or zero) + (previous balance * elapsed seconds)

By default a transfer will change a users twab.  However, as in the COMP token, users may delegate their balance to other users.

This will be most efficiently implemented *by integrating the logic into the token*.

## Gas Savings Idea

Save gas by using a circular buffer.  Each user has a twab history array of static length  (as in the [Uniswap V3 oracle observations](https://github.com/Uniswap/uniswap-v3-core/blob/b2c5555d696428c40c4b236069b3528b2317f3c1/contracts/UniswapV3Pool.sol#L99)).

Benefit of circular buffer: do not need to update the array length.  This occurs for both sender and receiver, saving ~10k gas.

Efficiently index head of buffer: current index is packed tightly with the balance.  Balance update is a single write.

*What should the buffer size be?*

6171 blocks / day => 6171 unique timestamps / day
6171 * 365 days = 2252415 unique timestamps / year

If we use 32 bits then:

(2**32) / 2252415 = 1900 years of storage.  Obscene.

So we could pack each word with 32 bits for timestamp and 224 bits for twab.
