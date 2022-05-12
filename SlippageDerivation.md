# Calculating Virtual CPMM LP by slippage and swap size

Let a be the amount of x we are exchanging to get b amount of y. Therefore:

(x + a) * (y - b) = k

We want to solve for x.

We know:

et = execution price of the trade = b/a
ex = exchange rate before trade = y/x

Let's now tune the liquidity to determine slippage. Let's say we want 1% slippage.

We want et/ex = 0.99

So we have:

et = 0.99*ex

We know the exchange rate and we know b, so we can solve for a:

b/a = 0.99*ex

b/(0.99*ex) = a

We know the exchange rate:

ex = y/x

now solve for y

x*ex = y

Here is our formula:

(x + a) * (y - b) = x * y
xy - bx + ay - ab = x * y
-bx + ay - ab = 0
ay = bx + ab

solve for x:
ay - ab = bx
x = (ay - ab)/b
x = (ay)/b - a

x = (a*x*ex)/b - a

x = (b*x*ex)/(b*0.99*ex) - b/(0.99*ex)
x - (b*x*ex)/(b*0.99*ex) = - b/(0.99*ex)
x(1 - b*ex/(b*0.99*ex)) = - b/(0.99*ex)

x = (-b / (0.99 * ex)) / (1 - b*ex/(b*0.99*ex))
x = (b / (0.99 * ex)) / (b*ex/(b*0.99*ex) - 1)


if b = 100
ex = 2

Then

x = (-100 / (0.99*2)) / (1 - (100*2)/(100 *0.99*2))
x = 5000

=>

2 = y/5000

10000 = y

Let's try it

x = 5000
y = 10000
trading a of x for b of y.
b = 100
solve for a

ay = bx + ab
ay - ab = bx
a(y - b) = bx
a = bx / (y - b)
a = 100 * 5000 / (10000 - 100)
a = 50.5

Right on point!

