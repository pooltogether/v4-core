// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicket.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@pooltogether/uniform-random-number/contracts/UniformRandomNumber.sol";
// import "./test/UniformRandomNumber.sol";

import "@pooltogether/fixed-point/contracts/FixedPoint.sol";

///@title TsunamiDrawCalculator is an ownable implmentation of an IDrawCalculator
contract TsunamiDrawCalculator is IDrawCalculator, OwnableUpgradeable {
  
  ///@notice Ticket associated with this calculator
  ITicket ticket;

  ///@notice Draw settings struct
  ///@param range Decimal representation of the range of number of bits consider within a 4-bit number. Max value 15.
  ///@param matchCardinality The number of 4-bit matches within the 256 word. Max value 64 (4*64=256).
  ///@param pickCost Amount of ticket required per pick
  ///@param distributions Array of prize distribution percentages, expressed in fraction form with base 1e18. Max sum of these <= 1 Ether.
  struct DrawSettings {
    uint8 range; 
    uint16 matchCardinality;
    uint224 pickCost;
    uint256[] distributions; // in order: index0: grandPrize, index1: runnerUp, etc. 
  }
  ///@notice storage of the DrawSettings associated with this Draw Calculator. NOTE: mapping? 
  DrawSettings public drawSettings;

  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(DrawSettings _drawSettings);

  ///@notice Emitted when the contract is initialized
  event Initialized(ITicket indexed _ticket, DrawSettings _drawSettings); // only emit ticket?

  ///@notice Initializer sets the initial parameters
  ///@param _ticket Ticket associated with this DrawCalculator
  ///@param _drawSettings Initial DrawSettings
  function initialize(ITicket _ticket, DrawSettings calldata _drawSettings) public initializer {
    __Ownable_init();
    ticket = _ticket;
    _setDrawSettings(_drawSettings);
    emit Initialized(_ticket, _drawSettings);
  }

  ///@notice Calulates the prize amount for a user at particular draws. Called by a Claimable Strategy.
  ///@param user User for which to calcualte prize amount
  ///@param winningRandomNumbers the winning random numbers for the Draws
  ///@param timestamps the timestamps at which the Draws occurred 
  ///@param prizes The prizes at those Draws
  ///@param data The encoded pick indices
  ///@return The amount of prize to award to the user 
  function calculate(address user, uint256[] calldata winningRandomNumbers, uint32[] calldata timestamps, uint256[] calldata prizes, bytes calldata data) 
    external override view returns (uint256){
    
    require(winningRandomNumbers.length == timestamps.length && timestamps.length == prizes.length, "DrawCalc/invalid-calculate-input-lengths");

    uint256[][] memory pickIndices = abi.decode(data, (uint256 [][]));
    require(pickIndices.length == timestamps.length, "DrawCalc/invalid-pick-indices-length");
    
    uint256[] memory userBalances = ticket.getBalances(user, timestamps); // CALL
    bytes32 userRandomNumber = keccak256(abi.encodePacked(user)); // hash the users address
    
    DrawSettings memory settings = drawSettings; //sload

    uint256 prize = 0;
    
    for (uint256 index = 0; index < winningRandomNumbers.length; index++) {
      prize += _calculate(winningRandomNumbers[index], prizes[index], userBalances[index], userRandomNumber, pickIndices[index], settings);
    }
    return prize;
  }

  ///@notice calculates the prize amount per Draw per users pick
  ///@param winningRandomNumber The Draw's winningRandomNumber
  ///@param prize The Draw's prize amount
  ///@param balance The users's balance for that Draw
  ///@param userRandomNumber the users randomNumber for that draw
  ///@param picks The users picks for that draw
  ///@param _drawSettings Params with the associated draw
  ///@return prize (if any) per Draw claim
  function _calculate(uint256 winningRandomNumber, uint256 prize, uint256 balance, bytes32 userRandomNumber, uint256[] memory picks, DrawSettings memory _drawSettings)
    internal view returns (uint256)
  {
    uint256 totalUserPicks = balance / _drawSettings.pickCost;
    uint256 pickPayoutPercentage = 0;

    for(uint256 index  = 0; index < picks.length; index++){
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(userRandomNumber, picks[index])));
      require(picks[index] <= totalUserPicks, "DrawCalc/insufficient-user-picks");
      pickPayoutPercentage += calculatePickFraction(randomNumberThisPick, winningRandomNumber, _drawSettings);
    }
    return (pickPayoutPercentage * prize) / 1 ether;
  }

  ///@notice Calculates the fraction of the Draw's Prize awardable to that user 
  ///@param randomNumberThisPick users random number for this Pick
  ///@param winningRandomNumber The winning number for this draw
  ///@param _drawSettings The parameters associated with the draw
  ///@return percentage of the Draw's Prize awardable to that user
  function calculatePickFraction(uint256 randomNumberThisPick, uint256 winningRandomNumber, DrawSettings memory _drawSettings)
    internal pure returns(uint256) {
    
    uint256 prizeFraction = 0;
    uint256 numberOfMatches = 0;
    
    for(uint256 matchIndex = 0; matchIndex < _drawSettings.matchCardinality; matchIndex++){      
      if(_getValueAtIndex(randomNumberThisPick, matchIndex, _drawSettings.range) == _getValueAtIndex(winningRandomNumber, matchIndex, _drawSettings.range)){
          numberOfMatches++;
      }          
    }
    
    uint256 prizeDistributionIndex = _drawSettings.matchCardinality - numberOfMatches; // prizeDistributionIndex == 0 : top prize, ==1 : runner-up prize etc
    
    // if prizeDistibution > distribution lenght -> there is no prize at that index
    if(prizeDistributionIndex < _drawSettings.distributions.length){ // they are going to receive prize funds
      uint256 numberOfPrizesForIndex = uint256(_drawSettings.range) ** prizeDistributionIndex;
      uint256 prizePercentageAtIndex = _drawSettings.distributions[prizeDistributionIndex];
      prizeFraction = prizePercentageAtIndex / numberOfPrizesForIndex;
    }
    return prizeFraction;
  }

  ///@notice helper function to return the unbiased 4-bit value within a word at a specified index
  ///@param word word to index
  ///@param index index to index (max 15)
  function _getValueAtIndex(uint256 word, uint256 index, uint8 _range) internal pure returns(uint256) {
    uint256 mask =  (uint256(15)) << (index * 4);
    return UniformRandomNumber.uniform(uint256((uint256(word) & mask) >> (index * 4)), _range);
  }

  ///@notice Set the DrawCalculators DrawSettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawSettings DrawSettings struct to set
  function setDrawSettings(DrawSettings calldata _drawSettings) external onlyOwner {
    _setDrawSettings(_drawSettings);
  }

  ///@notice Set the DrawCalculators DrawSettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawSettings DrawSettings struct to set
  function _setDrawSettings(DrawSettings calldata _drawSettings) internal {
    uint256 sumTotalDistributions = 0;
    uint256 distributionsLength = _drawSettings.distributions.length;
    
    require(_drawSettings.matchCardinality >= distributionsLength, "DrawCalc/matchCardinality-gt-distributions");
    require(_drawSettings.range <= 15, "DrawCalc/range-gt-15");
    require(_drawSettings.pickCost > 0, "DrawCalc/pick-gt-0");

    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    } 
    require(sumTotalDistributions <= 1 ether, "DrawCalc/distributions-gt-100%");
    
    drawSettings = _drawSettings; //sstore
    emit DrawSettingsSet(_drawSettings);
  }

}