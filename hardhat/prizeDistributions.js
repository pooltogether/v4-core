const { utils } = require('ethers');

const distributions = [
  utils.parseEther('0.9'),
  utils.parseEther('0.1'),
  utils.parseEther('0.1'),
  utils.parseEther('0.1'),
];

module.exports = distributions;
