// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicket.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pooltogether/uniform-random-number/contracts/UniformRandomNumber.sol";
// import "./test/UniformRandomNumber.sol";

import "@pooltogether/fixed-point/contracts/FixedPoint.sol";

/// match 256 bits -> range: 1, cardinality:64
contract TsunamiDrawCalculator is IDrawCalculator, OwnableUpgradeable {
  
  ///@notice Ticket associated with this calculator
  ITicket ticket;

  ///@notice Cost per pick
  uint256 constant PICK_COST = 1 ether;

  ///@notice Number of 4-bits to split the 256 bit word into (max 64: 4 * 64 = 256)
  uint256 public matchCardinality;

  ///@notice The number of bits to consider within the 4-bit word (expressed in decimal). 
  /// Max 15 which is max value represented by 4 bits
  uint256 public range;

  ///@notice Prize distribution breakdown expressed as a fraction of 1 ether (18 decimals). 0.2 = 20% of the prize etc
  uint256[] public distributions; // [grand prize, 2nd prize, ..]

  ///@notice Emitted when the contract is initialized
  event Initialized(ITicket indexed _ticket, uint256 _matchCardinality, uint256[] _distributions);

  ///@notice Emmitted when the match cardinality is set
  event MatchCardinalitySet(uint256 _matchCardinality);

  ///@notice Emitted when the Prize Distributions are set
  event PrizeDistributionsSet(uint256[] _distributions);

  ///@notice Emitted when the Prize Range is set
  event NumberRangeSet(uint256 range);

  ///@notice Initializer sets the initial parameters
  function initialize(ITicket _ticket, uint256 _matchCardinality, uint256[] memory _distributions, uint8 _range) public initializer {
    __Ownable_init();
    ticket = _ticket;
    matchCardinality = _matchCardinality;
    distributions = _distributions;
    range = _range;

    emit Initialized(_ticket, _matchCardinality, _distributions);
    emit MatchCardinalitySet(_matchCardinality);
    emit PrizeDistributionsSet(_distributions);
    emit NumberRangeSet(_range);
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

  ///@notice calculates the prize amount per Draw per users pick
  ///@param winningRandomNumber The Draw's winningRandomNumber
  ///@param prize The Draw's prize amount
  ///@param balance The users's balance for that Draw
  ///@param userRandomNumber the users randomNumber for that draw
  ///@param picks The users picks for that draw
  /// returns prize (if any) per Draw claim
  function _calculate(uint256 winningRandomNumber, uint256 prize, uint256 balance, bytes32 userRandomNumber, uint256[] memory picks)
    internal view returns (uint256)
  {
    uint256 totalUserPicks = balance / PICK_COST;
    // console.log("Calculator::_calculate totalUserPicks", totalUserPicks);
  
    uint256 pickPayoutPercentage = 0;

    //TODO: refactor to not sload these constants within the loop - simply moving is getting "stack too deep"
    uint256 _matchCardinality = matchCardinality; //sload
    uint256 _prizeDistributionLength = distributions.length; // sload

    for(uint256 index  = 0; index < picks.length; index++){ //NOTE: should this loop terminator be totalUserPicks
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(userRandomNumber, picks[index])));
      require(picks[index] <= totalUserPicks, "user does not have this many picks");
      
      console.log("calculate()::userRandomNumber is :", randomNumberThisPick);
      pickPayoutPercentage += calculatePickPercentage(randomNumberThisPick, winningRandomNumber, _matchCardinality, _prizeDistributionLength);
    }
    return (pickPayoutPercentage * prize) / 1 ether;

  }

  ///@notice Calculates the percentage of the Draw's Prize awardable to that user 
  function calculatePickPercentage(uint256 randomNumberThisPick, uint256 winningRandomNumber, uint256 _matchCardinality, uint256 distributionLength) 
    internal view returns(uint256) {
    
    uint256 percentage = 0;
    uint256 numberOfMatches = 0;
    uint256 _range = range; // SLOAD TODO move this higher in the loop structure
    // uint256[] prizeCounts = new 

    for(uint256 matchIndex = 0; matchIndex < _matchCardinality; matchIndex++){      
      uint256 userNumberAtIndex = _getValueAtIndex(randomNumberThisPick, matchIndex, _range);
      uint256 winningNumberAtIndex = _getValueAtIndex(winningRandomNumber, matchIndex, _range);

      console.log("attempting to match ", userNumberAtIndex, "and" ,winningNumberAtIndex);
      
      if(_getValueAtIndex(randomNumberThisPick, matchIndex, _range) == _getValueAtIndex(winningRandomNumber, matchIndex, _range)){
          console.log("There was a match!",userNumberAtIndex,winningNumberAtIndex);
          numberOfMatches++;
      }          
    }
    console.log("calculatePickPercentage::numberOfMatches ",numberOfMatches);
    uint256 prizeDistributionIndex = _matchCardinality - numberOfMatches; // prizeDistributionIndex == 0 : top prize, ==1 : runner-up prize etc
    
    console.log("calculatePickPercentage::prizeDistributionIndex ",prizeDistributionIndex);
    console.log("range ", _range);
    console.log("distribution length ", distributionLength);
    console.log("matchCardinality ", matchCardinality);
    
    
    // if prizeDistibution > distribution lenght -> there is no prize at that index
    if(prizeDistributionIndex < distributionLength){ // they are going to receive prize funds
      uint256 numberOfPrizesForIndex = _range ** prizeDistributionIndex;   /// number of prizes for Draw = range ** prizeDistrbutionIndex
      console.log("calculatePickPercentage::numberOfPrizesForIndex ",numberOfPrizesForIndex);
      percentage = distributions[prizeDistributionIndex] / numberOfPrizesForIndex; // TODO: use FixedPoint   -- direct assign vs. += ??
      console.log("percentage of prize for pick ",percentage);
    }
    return percentage;
  }

  ///@notice helper function to return the 4-bit value within a word at a specified index
  ///@param word word to index
  ///@param index index to index (max 15)
  function _getValueAtIndex(uint256 word, uint256 index, uint256 _range) internal view returns(uint256) {
    uint256 mask =  (uint256(15)) << (index * 4);
    return UniformRandomNumber.uniform(uint256((uint256(word) & mask) >> (index * 4)), _range);
  }

  ///@notice Set the Prize Range for the Draw
  ///@param _range The range to set. Max 15.
  function setNumberRange(uint256 _range) external onlyOwner {
    require(_range < 16, "prize range too large");
    range = _range;
    emit NumberRangeSet(_range);
  }

  ///@notice set the match cardinality. only callable by contract owner
  ///@param _matchCardinality the match cardinality to be set
  function setMatchCardinality(uint256 _matchCardinality) external onlyOwner {
    require(_matchCardinality >= distributions.length, "match cardinality lt distributions");
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
    require(sum <= 1 ether, "sum of distributions too large"); //NOTE: should we also enforce that == 1 ether? Does not doing this mess up the distribution?

    require(_distributions.length <= matchCardinality, "distributions gt cardinality");
    distributions = _distributions; //sstore
    emit PrizeDistributionsSet(_distributions);
  }

}