#!/usr/bin/env node
const chalk = require('chalk')

function dim(...args) {
    console.log(chalk.dim(...args))
}

// given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
function getAmountOut(amountIn, x, y) {
    return (amountIn * y) / (x + amountIn);
}

// given an output amount of an asset and pair reserves, returns a required input amount of the other asset
function getAmountIn(amountOut, reserveIn, reserveOut) {
    return (reserveIn * amountOut) / (reserveOut - amountOut)
}

/// @notice marketRate is yield / pool
function computeTradeProfit(poolAmountIn, yieldAmountOut, marketRate) {
    const poolCostInTermsOfYield = poolAmountIn * marketRate
    return yieldAmountOut > poolCostInTermsOfYield ? yieldAmountOut - poolCostInTermsOfYield : 0
}

function buyback(accruedYield, cpmm) {
    // swapping yield for pool
    const poolAmountOut = getAmountOut(accruedYield, cpmm.yieldVirtualReserve, cpmm.poolVirtualReserve)
    // console.log(chalk.cyan(`$$$ Buyback ${poolAmountOut} POOL for ${accruedYield} USDC`))
    return {
        ...cpmm,
        yieldVirtualReserve: cpmm.yieldVirtualReserve + accruedYield,
        poolVirtualReserve: cpmm.poolVirtualReserve - poolAmountOut
    }
}

function swap(yieldAmountOut, accruedYield, cpmm) {

    // buyback
    cpmm = buyback(accruedYield, cpmm)

    // swap
    const poolAmountIn = getAmountIn(yieldAmountOut, cpmm.poolVirtualReserve, cpmm.yieldVirtualReserve)
    const yieldVirtualReserve = cpmm.yieldVirtualReserve - yieldAmountOut
    const poolVirtualReserve = cpmm.poolVirtualReserve + poolAmountIn
    // dim(`swap k: ${parseInt(poolVirtualReserve * yieldVirtualReserve)}`)

    const remainingYield = accruedYield - yieldAmountOut
    const purchasePortion = yieldAmountOut / accruedYield
    dim(`\t\t\tremaining ${remainingYield}, ${accruedYield}, ${yieldAmountOut}, purchasePortion: ${purchasePortion}`)

    // Apply downward pressure to drive price down.
    let fraction = 0.3

    const additionalDownwardPressureYieldOut = yieldAmountOut*fraction
    const additionalDownwardPressurePoolIn = getAmountIn(additionalDownwardPressureYieldOut, poolVirtualReserve, yieldVirtualReserve)
    const yieldVirtualReserveWithDownwardPressure = yieldVirtualReserve - additionalDownwardPressureYieldOut
    const poolVirtualReserveWithDownwardPressure = poolVirtualReserve + additionalDownwardPressurePoolIn

    // accrued yield is a sawtooth. So we apply a low-pass filter to calculate a moving average. over X seconds.
    const alpha = 0.95
    const accruedYieldMovingAverage = (cpmm.accruedYieldMovingAverage*alpha) + accruedYield * (1 - alpha)

    // now, we want to ensure that the accrued yield is always a small fraction of virtual LP position.
    const multiplier = accruedYieldMovingAverage / (yieldVirtualReserveWithDownwardPressure*0.05)
    dim(`multiplier: ${multiplier}`)

    const resultCpmm = {
        yieldVirtualReserve: multiplier * yieldVirtualReserveWithDownwardPressure,
        poolVirtualReserve: multiplier * poolVirtualReserveWithDownwardPressure,
        accruedYieldMovingAverage
    }

    return resultCpmm
}

function computeExactAmountIn(yieldAmountOut, accruedYield, cpmm) {
    cpmm = buyback(accruedYield, cpmm)
    // now run the user swap
    return getAmountIn(yieldAmountOut, cpmm.poolVirtualReserve, cpmm.yieldVirtualReserve)
}

function findOptimalAmountOut(accruedYield, cpmm, marketRate) {
    let bestYieldAmountOut = 0
    let bestPoolAmountIn = 0
    let bestProfit = 0
    // steps of 1%
    let stepSize = 0.1 * accruedYield
    for (let yieldAmountOut = stepSize; yieldAmountOut <= accruedYield; yieldAmountOut += stepSize) {
        const poolAmountIn = computeExactAmountIn(yieldAmountOut, accruedYield, cpmm)
        const profit = computeTradeProfit(poolAmountIn, yieldAmountOut, marketRate)
        // dim(`Trading ${poolAmountIn} for ${yieldAmountOut} with profit of ${profit}`)
        if (profit > bestProfit) {
            bestYieldAmountOut = yieldAmountOut
            bestPoolAmountIn = poolAmountIn
            bestProfit = profit
        }
    }
    return {
        yieldAmountOut: bestYieldAmountOut,
        poolAmountIn: bestPoolAmountIn,
        profit: bestProfit
    }
}

async function run() {

    let marketRates = {
        0: 10,
        50: 12,
        80: 14,
        100: 16,
        140: 18,
        150: 20,
        180: 22,
        200: 24,
        240: 26,
        280: 28,
        320: 30,
        350: 32,
        400: 30,
        450: 22,
        500: 16,
        600: 10,
        700: 8
    }

    let accrualRates = {
        0: 10,
        // 50: 20,
        100: 100,
        // 150: 80,
        // 200: 160,
        400: 1000,
        // 300: 640,
        800: 10000
    }

    // x = yield
    // y = POOL
    // higher virtual LP values mean 
    let cpmm = {
        yieldVirtualReserve: 500,
        poolVirtualReserve: 50,
        accruedYieldMovingAverage: 0
    }

    const DURATION = 750
    const MIN_PROFIT = 1

    let marketRate = marketRates[0]
    let accrualRate = accrualRates[0]
    let accruedYield = 0

    let poolIncome = 0
    let arbCount = 0

    for (let time = 0; time < DURATION; time++) {
        if (marketRates[time] > 0) {
            marketRate = marketRates[time]
        }
        if (accrualRates[time] > 0) {
            accrualRate = accrualRates[time]
        }
        accruedYield += accrualRate

        const {
            yieldAmountOut,
            poolAmountIn,
            profit
        } = findOptimalAmountOut(accruedYield, cpmm, marketRate)
        
        if (profit >= MIN_PROFIT) {
            arbCount++;
            cpmm = swap(yieldAmountOut, accruedYield, cpmm)
            let swapExchangeRate = yieldAmountOut / poolAmountIn
            poolIncome += poolAmountIn
            let efficiency = marketRate / swapExchangeRate
            accruedYield -= yieldAmountOut

            const details = [
                `@ ${time} efficiency ${parseInt(efficiency * 100)}`,
                `moving average: ${cpmm.accruedYieldMovingAverage}`,
                `vr yield: ${cpmm.yieldVirtualReserve}`,
                `vr pool: ${cpmm.poolVirtualReserve}`,
                // `sold ${poolAmountIn} POOL`,
                // `bought ${yieldAmountOut} USDC`,
                // `profit ${profit} USDC`, 
                `swapExchangeRate ${swapExchangeRate}`,
                `remainingYield ${accruedYield}`
            ]

            console.log(chalk.green(details.join('\n\t')))
        }
    }

    console.log(chalk.cyan(`\n${arbCount} arbs brough in ${poolIncome} POOL`))
}

run()
