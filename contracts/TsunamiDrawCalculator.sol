// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicket.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TsunamiDrawCalculator is IDrawCalculator, OwnableUpgradeable {
  ITicket ticket;

  uint256 constant PICK_COST = 1 ether;

  uint256 public matchCardinality;

  uint256[] public distributions; // [grandprize, 2nd prize, ..]

  function initialize(ITicket _ticket, uint256 _matchCardinality, uint256[] memory _distributions) public initializer {
    __Ownable_init();
    ticket = _ticket;
    matchCardinality = _matchCardinality;
    distributions = _distributions;

    // todo event
  }

  function calculate(address user, uint256[] calldata randomNumbers, uint256[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) external override view returns (uint256){
    require(randomNumbers.length == timestamps.length && timestamps.length == prizes.length, "invalid-calculate-input-lengths");

    uint256[][] memory pickIndices = abi.decode(data, (uint256 [][]));
    uint256 prize;
    require(pickIndices.length == timestamps.length, "invalid-pick-indices-length");
    uint256[] memory balances = ticket.getBalances(user, timestamps);

    bytes32 userRandomNumber = keccak256(abi.encodePacked(user));
    for (uint256 index = 0; index < timestamps.length; index++) {
      prize += _calculate(randomNumbers[index], prizes[index], balances[index], userRandomNumber, pickIndices[index]);
    }

    return prize;
  }

  function setMatchCardinality(uint256 _matchCardinality) external {
    matchCardinality = _matchCardinality;
  }

  function setPrizeDistribution(uint256[] memory _distributions) external {
    uint256 sum;
    for(uint256 i = 0; i < _distributions.length; i++){
      sum += _distributions[i];
    }
    require(sum <= 1 ether, "sum of distributions too large");

    require(_distributions.length <= matchCardinality, "distributions gt cardinality");
    distributions = _distributions; //sstore
  }

  function _calculate(uint256 randomNumber, uint256 prize, uint256 totalSupply, uint256 balance, bytes32 userRandomNumber, uint256[] calldata picks)
    internal view returns (uint256)
  {
    uint256 totalUserPicks = totalSupply / PICK_COST;

    uint256 payout = 0;

    uint256 _matchCardinality = matchCardinality; //sload
    uint256 distributionLength = distributions.length;

    for(uint256 index  = 0; index < picks.length; index++){
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(randomNumber, picks[index])));
      payout += calculatePickPercentage(randomNumberThisPick, randomNumber, _matchCardinality, distributionLength);
    }
    return (payout * prize)/ 1 ether;

  }

  function calculatePickPercentage(uint256 randomNumberThisPick, uint256 randomNumber, uint256 _matchCardinality, uint256 distributionLength) internal view returns(uint256) {
    uint256 percentage = 0;
    uint256 numberOfMatches = 0;
    
    for(uint256 matchIndex = 0; matchIndex < _matchCardinality; matchIndex++){       
      if(getValueAtIndex(randomNumberThisPick, matchIndex) == getValueAtIndex(randomNumber, matchIndex)){
          numberOfMatches++;
      }          
    }
    uint256 prizeDistributionIndex = _matchCardinality - numberOfMatches;
    if(prizeDistributionIndex < distributionLength){ // they are going to receive prize funds
      percentage += distributions[prizeDistributionIndex]; // TODO: use FixedPoint
    }
    return percentage;
  }

  function getValueAtIndex(uint256 allValues, uint256 index) internal pure returns(uint256) {
    uint256 mask =  (type(uint32).max | uint256(0)) << (index * 4);
    return uint256((uint256(allValues) & mask) >> (index * 4));
  }

}