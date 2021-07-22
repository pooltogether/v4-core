// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";
import "./TsunamiPrizeStrategy.sol";
// Libraries & Inheritance



contract WaveModel is IWaveModel {
  
  uint256 constant PICK_COST = 1 ether;

  uint256 public matchCardinality;

  uint256[] public distributions; // [grandprize, 2nd prize, ..]

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

  function calculate(uint256 randomNumber, uint256 prize, uint256 totalSupply, uint256 balance, bytes32 userRandomNumber, uint256[] calldata picks)
    external override view returns (uint256)
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

  function calculatePickPercentage(uint256 randomNumberThisPick, uint256 randomNumber, uint256 _matchCardinality, uint256 distributionLength) internal view returns(uint256){
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

  function getValueAtIndex(uint256 allValues, uint256 index) internal pure returns(uint256){
    uint256 mask =  (type(uint32).max | uint256(0)) << (index * 4);
    return uint256((uint256(allValues) & mask) >> (index * 4));
  }


}