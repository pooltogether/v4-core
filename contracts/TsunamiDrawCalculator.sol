// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
import "hardhat/console.sol";

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicketTwab.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

///@title TsunamiDrawCalculator is an ownable implmentation of an IDrawCalculator
contract TsunamiDrawCalculator is IDrawCalculator, OwnableUpgradeable {
  ITicketTwab ticket;

  ///@notice Draw settings struct
  ///@param bitRangeValue Decimal representation of bitRangeSize
  ///@param bitRangeSize Number of bits to consider matching
  ///@param matchCardinality The bitRangeSize's to consider in the 256 random numbers. Must be > 1 and < 256/bitRangeSize
  ///@param pickCost Amount of ticket balance required per pick
  ///@param distributions Array of prize distribution percentages, expressed in fraction form with base 1e18. Max sum of these <= 1 Ether.
  struct DrawSettings {
    uint8 bitRangeValue;
    uint8 bitRangeSize;
    uint16 matchCardinality;
    uint224 pickCost;
    uint256[] distributions; // in order: index0: grandPrize, index1: runnerUp, etc.
  }
  ///@notice storage of the DrawSettings associated with this Draw Calculator. NOTE: mapping? store elsewhere?
  DrawSettings public drawSettings;

  ///@notice Emitted when the DrawParams are set/updated
  event DrawSettingsSet(DrawSettings _drawSettings);

  ///@notice Emitted when the contract is initialized
  event Initialized(ITicketTwab indexed _ticket);

  ///@notice Initializer sets the initial parameters
  ///@param _ticket Ticket associated with this DrawCalculator
  ///@param _drawSettings Initial DrawSettings
  function initialize(ITicketTwab _ticket, DrawSettings calldata _drawSettings) public initializer {
    __Ownable_init();
    ticket = _ticket;

    _setDrawSettings(_drawSettings);
    emit Initialized(_ticket);
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
    uint256 pickPayoutFraction = 0;

    for(uint256 index  = 0; index < picks.length; index++){
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(userRandomNumber, picks[index])));
      require(picks[index] < totalUserPicks, "DrawCalc/insufficient-user-picks");
      pickPayoutFraction += calculatePickFraction(randomNumberThisPick, winningRandomNumber, _drawSettings);
    }
    return (pickPayoutFraction * prize) / 1 ether;
  }

  ///@notice Calculates the fraction of the Draw's Prize awardable to that user
  ///@param randomNumberThisPick users random number for this Pick
  ///@param winningRandomNumber The winning number for this draw
  ///@param _drawSettings The parameters associated with the draw
  ///@return percentage of the Draw's Prize awardable to that user
  function calculatePickFraction(uint256 randomNumberThisPick, uint256 winningRandomNumber, DrawSettings memory _drawSettings)
    internal view returns(uint256) {

    uint256 prizeFraction = 0;
    uint256 numberOfMatches = 0;

    uint256 _matchCardinality = _drawSettings.matchCardinality; // how many bitRangeSize to consider within the 256 bits. Max 256.
    uint8 _bitRangeSize = _drawSettings.bitRangeSize; // how many bits we attempt to match - must satisfy 1 <= bitRangeSize <= _matchCardinality
    uint8 _bitRangeMaskValue = _drawSettings.bitRangeValue;  //decimal representation of _bitRangeSize must be equal to (2 ^ _bitRangeSize) - 1 //for gas efficiency only.

    for(uint256 matchIndex = 0; matchIndex < _matchCardinality; matchIndex++){
      uint16 _matchIndexOffset = uint16(matchIndex * _bitRangeSize);

      if(_findBitMatchesAtIndex(randomNumberThisPick, winningRandomNumber, _matchIndexOffset, _bitRangeMaskValue)){
          numberOfMatches++;
        }
    }

    uint256 prizeDistributionIndex = _matchCardinality - numberOfMatches; // prizeDistributionIndex == 0 : top prize, ==1 : runner-up prize etc

    // if prizeDistibution > distribution lenght -> there is no prize at that index
    if(prizeDistributionIndex < _drawSettings.distributions.length){ // they are going to receive prize funds
      uint256 numberOfPrizesForIndex = uint256(_bitRangeSize) ** prizeDistributionIndex;
      uint256 prizePercentageAtIndex = _drawSettings.distributions[prizeDistributionIndex];
      prizeFraction = prizePercentageAtIndex / numberOfPrizesForIndex;
    }
    return prizeFraction;
  }

  ///@notice helper function to return if the bits in a word match at a particular index
  ///@param word1 word1 to index and match
  ///@param word2 word2 to index and match
  ///@param indexOffset 0 start index including 4-bit offset (i.e. 8 observes index 2 = 4 * 2)
  ///@param _bitRangeMaskValue _bitRangeMaskValue must be equal to (_bitRangeSize ^ 2) - 1
  ///@return true if there is a match, false otherwise
  function _findBitMatchesAtIndex(uint256 word1, uint256 word2, uint256 indexOffset, uint8 _bitRangeMaskValue)
    internal pure returns(bool) {
    // generate a mask of _bitRange length at the specified offset
    uint256 mask = (uint256(_bitRangeMaskValue)) << indexOffset;

    // find bits at index for word1
    uint256 bits1 = (uint256(word1) & mask);

    // find bits at index for word2
    uint256 bits2 = (uint256(word2) & mask);

    return bits1 == bits2;
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
    require(_drawSettings.bitRangeValue == (2 ** _drawSettings.bitRangeSize) - 1, "DrawCalc/bitRangeValue-incorrect");
    require(_drawSettings.bitRangeSize <= 256 / _drawSettings.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_drawSettings.pickCost > 0, "DrawCalc/pick-gt-0");

    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    }

    require(sumTotalDistributions <= 1 ether, "DrawCalc/distributions-gt-100%");
    drawSettings = _drawSettings; //sstore
    emit DrawSettingsSet(_drawSettings);
  }

}
