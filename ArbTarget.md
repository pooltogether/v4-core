Slippage: 5%
Initial Arb Target: 500
Initial exchange rate: X


Then the arb target is when we expect them to buy to get a discount. It determines the LP size.

After a user purchases, we set the new arb target based on the current arb + previous.

Does this drive arb target to zero?

PRBMath.SD59x18 memory one = PRBMath.SD59x18(1 ether);

desiredExchangeRate = (1-slippage)*exchangeRate

want = arbTarget.div(desiredExchangeRate).div(
    arbTarget.mul(exchangeRate).div(arbTarget.mul(desiredExchangeRate)).sub(one)
);

ay = bx + ab

b = (ay)/(x+a)
