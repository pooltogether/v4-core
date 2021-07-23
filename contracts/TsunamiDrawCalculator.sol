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

  uint256[] public distributions; // [grand prize, 2nd prize, ..]

  event Initialized(ITicket indexed _ticket, uint256 _matchCardinality, uint256[] _distributions);

  event MatchCardinalitySet(uint256 _matchCardinality);

  event PrizeDistributionsSet(uint256[] _distributions);

  function initialize(ITicket _ticket, uint256 _matchCardinality, uint256[] memory _distributions) public initializer {
    __Ownable_init();
    ticket = _ticket;
    matchCardinality = _matchCardinality;
    distributions = _distributions;

    emit Initialized(_ticket, _matchCardinality, _distributions);
  }

  ///@notice Calulates the prize amount for a user at particular draws. Called by a Claimable Strategy.
  ///@param user User for which to calcualte prize amount
  ///@param winningRandomNumbers the winning random numbers for the Draws
  ///@param timestamps the timestamps at which the Draws occurred 
  ///@param prizes The prizes at those Draws
  ///@param data The encoded pick indices
  function calculate(address user, uint256[] calldata winningRandomNumbers, uint32[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) 
    external override view returns (uint256){
    
    require(winningRandomNumbers.length == timestamps.length && timestamps.length == prizes.length, "invalid-calculate-input-lengths");

    uint256[][] memory pickIndices = abi.decode(data, (uint256 [][]));
    require(pickIndices.length == timestamps.length, "invalid-pick-indices-length");
    
    uint256[] memory userBalances = ticket.getBalances(user, timestamps);
    bytes32 userRandomNumber = keccak256(abi.encodePacked(user)); // hash the users address
    console.log("calculate()::userRandomNumber is :");
    console.logBytes32( userRandomNumber);
    
    uint256 prize = 0;
    
    for (uint256 index = 0; index < timestamps.length; index++) {
      prize += _calculate(winningRandomNumbers[index], prizes[index], userBalances[index], userRandomNumber, pickIndices[index]);
    }

    return prize;
  }



  /// returns prize (if any) per Draw claim
  function _calculate(uint256 winningRandomNumber, uint256 prize, uint256 balance, bytes32 userRandomNumber, uint256[] memory picks)
    internal view returns (uint256)
  {
    uint256 totalUserPicks = balance / PICK_COST;
    console.log("Calculator::_calculate totalUserPicks", totalUserPicks);
    console.log("Calculator::balance", balance);
    uint256 pickPayoutPercentage = 0;

    //TODO: refactor to not sload these constants within the loop - simply moving is getting "stack too deep"
    uint256 _matchCardinality = matchCardinality; //sload
    uint256 _prizeDistributionLength = distributions.length; // sload

    for(uint256 index  = 0; index < picks.length; index++){ // should this be totalUserPicks vs. 
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(userRandomNumber, picks[index])));
      console.log("calculate()::userRandomNumber is :", randomNumberThisPick);
      pickPayoutPercentage += calculatePickPercentage(randomNumberThisPick, winningRandomNumber, _matchCardinality, _prizeDistributionLength);
    }
    return (pickPayoutPercentage * prize) / 1 ether;

  }

  function calculatePickPercentage(uint256 randomNumberThisPick, uint256 winningRandomNumber, uint256 _matchCardinality, uint256 distributionLength) 
    internal view returns(uint256) {
    
    uint256 percentage = 0;
    uint256 numberOfMatches = 0;
    
    for(uint256 matchIndex = 0; matchIndex < _matchCardinality; matchIndex++){       
      console.log("attempting to match ", getValueAtIndex(randomNumberThisPick, matchIndex));
      console.log("with: ", getValueAtIndex(winningRandomNumber, matchIndex));
      if(getValueAtIndex(randomNumberThisPick, matchIndex) == getValueAtIndex(winningRandomNumber, matchIndex)){
          numberOfMatches++;
      }          
    }
    console.log("calculatePickPercentage::numberOfMatches ",numberOfMatches);
    uint256 prizeDistributionIndex = _matchCardinality - numberOfMatches; // prizeDistributionIndex == 0 : top prize, ==1 : runner-up prize etc
    console.log("calculatePickPercentage::prizeDistributionIndex ",prizeDistributionIndex);
    
    if(prizeDistributionIndex < distributionLength){ // they are going to receive prize funds
      percentage += distributions[prizeDistributionIndex]; // TODO: use FixedPoint
    }
    return percentage;
  }

  ///@notice helper function to return the 4-bit value within a word at a specified index
  ///@param word word to index
  ///@param index index to index
  function getValueAtIndex(uint256 word, uint256 index) internal pure returns(uint256) {
    uint256 mask =  (type(uint32).max | uint256(0)) << (index * 4);
    return uint256((uint256(word) & mask) >> (index * 4));
  }

  ///@notice set the match cardinality. only callable by contract owner
  ///@param _matchCardinality the match cardinality to be set
  function setMatchCardinality(uint256 _matchCardinality) external onlyOwner {
    matchCardinality = _matchCardinality;
    emit MatchCardinalitySet(_matchCardinality);
  }

  ///@notice sets the prize distribution. only callable by contract owner
  ///@param _distributions array of prize distributions to be set denoted in base 1e18. Must be less than 100%
  function setPrizeDistribution(uint256[] memory _distributions) external onlyOwner {
    uint256 sum = 0;
    for(uint256 i = 0; i < _distributions.length; i++){
      sum += _distributions[i];
    }
    require(sum <= 1 ether, "sum of distributions too large");

    require(_distributions.length <= matchCardinality, "distributions gt cardinality");
    distributions = _distributions; //sstore
    emit PrizeDistributionsSet(_distributions);
  }

}