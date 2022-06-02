const { BigNumber, constants } = require('ethers');


/* ================================================================================ */
/* GaugeController                                                                  */
/* ================================================================================ */
task('GaugeController:deposit')
  .addPositionalParam('to', 'to')
  .addPositionalParam('amount', 'Amount to deposit')
  .setAction(async function ({ amount, to }, taskArgs, { ethers }) {

});

task('GaugeController:withdraw')
  .addPositionalParam('to', 'to')
  .addPositionalParam('amount', 'Amount to withdraw')
  .setAction(async function ({ amount, to }, taskArgs, { ethers }) {

});
