// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicketTwab.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

///@title TsunamiDrawCalculator is an ownable implmentation of an IDrawCalculator
contract TsunamiDrawCalculator is IDrawCalculator, OwnableUpgradeable {
  
  ///@notice Ticket associated with DrawCalculator
  ITicketTwab ticket;

  ///@notice storage of the DrawSettings associated with this Draw Calculator. NOTE: mapping? store elsewhere?
  DrawSettings public drawSettings;

  /* ============ Structs ============ */

  ///@notice Draw settings struct
  ///@param bitRangeSize Decimal representation of bitRangeSize
  ///@param matchCardinality The bitRangeSize's to consider in the 256 random numbers. Must be > 1 and < 256/bitRangeSize
  ///@param pickCost Amount of ticket balance required per pick
  ///@param distributions Array of prize distribution percentages, expressed in fraction form with base 1e18. Max sum of these <= 1 Ether. ordering: index0: grandPrize, index1: runnerUp, etc.
  struct DrawSettings {
    uint8 bitRangeSize;
    uint16 matchCardinality;
    uint224 pickCost;
    uint128[] distributions;
  }

  /* ============ Events ============ */

  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(DrawSettings _drawSettings);

  ///@notice Emitted when the contract is initialized
  event Initialized(ITicketTwab indexed _ticket);


  /* ============ External Functions ============ */

  ///@notice Initializer sets the initial parameters
  ///@param _ticket Ticket associated with this DrawCalculator
  ///@param _drawSettings Initial DrawSettings
  function initialize(ITicketTwab _ticket, DrawSettings calldata _drawSettings) public initializer {
    __Ownable_init();
    ticket = _ticket;

    _setDrawSettings(_drawSettings);
    emit Initialized(_ticket);
  }

  ///@notice Calculates the expected prize fraction per DrawSettings and prizeDistributionIndex
  ///@param _drawSettings DrawSettings struct for Draw
  ///@param prizeDistributionIndex Index of the prize distribution array to calculate
  ///@return returns the fraction of the total prize
  function calculatePrizeDistributionFraction(DrawSettings calldata _drawSettings, uint256 prizeDistributionIndex) external view returns(uint256){
    return _calculatePrizeDistributionFraction(_drawSettings, prizeDistributionIndex);
  }

  ///@notice Set the DrawCalculators DrawSettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawSettings DrawSettings struct to set
  function setDrawSettings(DrawSettings calldata _drawSettings) external onlyOwner {
    _setDrawSettings(_drawSettings);
  }

  ///@notice Calulates the prize amount for a user for Multiple Draws. Typically called by a ClaimableDraw.
  ///@param user User for which to calcualte prize amount
  ///@param winningRandomNumbers the winning random numbers for the Draws
  ///@param timestamps the timestamps at which the Draws occurred
  ///@param prizes The prizes at those Draws
  ///@param pickIndicesForDraws The encoded pick indices for all Draws. Expected to be just indices of winning claims. Populated values must be less than totalUserPicks.
  ///@return An array of prizes awardable
  function calculate(address user, uint256[] calldata winningRandomNumbers, uint32[] calldata timestamps, uint256[] calldata prizes, bytes calldata pickIndicesForDraws)
    external override view returns (uint96[] memory){

    require(winningRandomNumbers.length == timestamps.length && timestamps.length == prizes.length, "DrawCalc/invalid-calculate-input-lengths");

    uint96[] memory prizesAwardable = new uint96[](prizes.length);

    uint256[][] memory pickIndices = abi.decode(pickIndicesForDraws, (uint256 [][]));
    require(pickIndices.length == timestamps.length, "DrawCalc/invalid-pick-indices-length");

    uint256[] memory userBalances = ticket.getBalances(user, timestamps); // CALL
    bytes32 userRandomNumber = keccak256(abi.encodePacked(user)); // hash the users address

    DrawSettings memory settings = drawSettings; //sload

    // calculate for each Draw passed
    for (uint256 index = 0; index < winningRandomNumbers.length; index++) {
      prizesAwardable[index] = _calculate(winningRandomNumbers[index], prizes[index], userBalances[index], userRandomNumber, pickIndices[index], settings);
    }
    return prizesAwardable;
  }

  /* ============ Internal Functions ============ */

  ///@notice calculates the prize amount per Draw per users pick
  ///@param winningRandomNumber The Draw's winningRandomNumber
  ///@param prize The Draw's prize amount
  ///@param balance The users's balance for that Draw
  ///@param userRandomNumber the users randomNumber for that draw
  ///@param picks The users picks for that draw
  ///@param _drawSettings Params with the associated draw
  ///@return prize (if any) per Draw claim
  function _calculate(uint256 winningRandomNumber, uint256 prize, uint256 balance, bytes32 userRandomNumber, uint256[] memory picks, DrawSettings memory _drawSettings)
    internal view returns (uint96)
  {
    
    uint256 totalUserPicks = balance / _drawSettings.pickCost;
    uint256[] memory prizeCounts =  new uint256[](_drawSettings.distributions.length);
    uint256[] memory masks =  createBitMasks(_drawSettings);

    // for each pick find number of matching numbers and calculate prioze distribution index
    for(uint256 index  = 0; index < picks.length; index++){
      
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(userRandomNumber, picks[index])));
      require(picks[index] < totalUserPicks, "DrawCalc/insufficient-user-picks");
      
      uint256 distributionIndex =  calculateDistributionIndex(randomNumberThisPick, winningRandomNumber, masks);
      if(distributionIndex < _drawSettings.distributions.length) { // there is prize for this distributionIndex
        prizeCounts[distributionIndex]++;
      } 
    }

    // now calculate prizeFraction given prize counts
    uint256 prizeFraction = 0;
    for(uint256 prizeCountIndex = 0; prizeCountIndex < _drawSettings.distributions.length; prizeCountIndex++) { 
      if(prizeCounts[prizeCountIndex] > 0) {
        prizeFraction += _calculatePrizeDistributionFraction(_drawSettings, prizeCountIndex) * prizeCounts[prizeCountIndex];
      }
    }
    // return the absolute amount of prize awardable
    return uint96((prizeFraction * prize) / 1 ether); // div by 1 ether as prize distributions are base 1e18
  }

  ///@notice Calculates the distribution index given the random numbers and masks
  ///@param randomNumberThisPick users random number for this Pick
  ///@param winningRandomNumber The winning number for this draw
  ///@param masks The pre-calculate bitmasks for the drawSettings
  ///@return The position within the prize distribution array (0 = top prize, 1 = runner-up prize, etc)
  function calculateDistributionIndex(uint256 randomNumberThisPick, uint256 winningRandomNumber, uint256[] memory masks)
    internal view returns (uint256) 
  {

    uint256 numberOfMatches = 0;
    for(uint256 matchIndex = 0; matchIndex < masks.length; matchIndex++) {
      if((uint256(randomNumberThisPick) & masks[matchIndex]) == (uint256(winningRandomNumber) & masks[matchIndex])) {
        numberOfMatches++;
      }
    }
    return masks.length - numberOfMatches;
  }


  ///@notice helper function to create bitmasks equal to the matchCardinality
  ///@return An array of bitmasks
  function createBitMasks(DrawSettings memory _drawSettings) 
    internal view returns (uint256[] memory)
  {
    uint256[] memory masks = new uint256[](_drawSettings.matchCardinality);
    
    uint256 _bitRangeMaskValue = (2 ** _drawSettings.bitRangeSize) - 1; // get a decimal representation of bitRangeSize
    
    for(uint256 maskIndex = 0; maskIndex < _drawSettings.matchCardinality; maskIndex++){
      uint16 _matchIndexOffset = uint16(maskIndex * _drawSettings.bitRangeSize);
      masks[maskIndex] = _bitRangeMaskValue << _matchIndexOffset;
    }
    
    return masks;
  }


  ///@notice Calculates the expected prize fraction per DrawSettings and prizeDistributionIndex
  ///@param _drawSettings DrawSettings struct for Draw
  ///@param prizeDistributionIndex Index of the prize distribution array to calculate
  ///@return returns the fraction of the total prize (base 1e18)
  function _calculatePrizeDistributionFraction(DrawSettings memory _drawSettings, uint256 prizeDistributionIndex) internal pure returns (uint256) 
  {
    uint256 numberOfPrizesForIndex = (2 ** uint256(_drawSettings.bitRangeSize)) ** prizeDistributionIndex;
    uint256 prizePercentageAtIndex = _drawSettings.distributions[prizeDistributionIndex];
    return prizePercentageAtIndex / numberOfPrizesForIndex;
  } 

  ///@notice Set the DrawCalculators DrawSettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawSettings DrawSettings struct to set
  function _setDrawSettings(DrawSettings calldata _drawSettings) internal {
    uint256 sumTotalDistributions = 0;
    uint256 distributionsLength = _drawSettings.distributions.length;

    require(_drawSettings.matchCardinality >= distributionsLength, "DrawCalc/matchCardinality-gt-distributions");
    require(_drawSettings.bitRangeSize <= 256 / _drawSettings.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_drawSettings.pickCost > 0, "DrawCalc/pick-cost-gt-0");

    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    }

    require(sumTotalDistributions <= 1 ether, "DrawCalc/distributions-gt-100%");
    drawSettings = _drawSettings; //sstore
    emit DrawSettingsSet(_drawSettings);
  }

}
