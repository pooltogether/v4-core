// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicket.sol";
import "./ClaimableDraw.sol";
import "./libraries/DrawLib.sol";
import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";

/**
  * @title  PoolTogether V4 DrawCalculator
  * @author PoolTogether Inc Team
  * @notice The TsunamiDrawCalculator calculates a user's claimable prize by using the combined entropy of
            Draw.randomWinningNumber, wallet address and supplied pickIndices. Prize payouts are divided
            into multiple tiers: grand prize, second place, third place, etc... Prizes can be claimed
            by supplying matching winning numbers via the user allotted pickIndices. A user with a higher
            average weighted balance will be given a large number of pickIndices to choose from, and thus a 
            higher chance to win the highest possible prize payouts.

  
*/
contract TsunamiDrawCalculator is IDrawCalculator, OwnerOrManager {
  
  uint256 constant MAX_CARDINALITY = 256;

  /// @notice Ticket associated with DrawCalculator
  ITicket ticket;

  /// @notice The stored history of draw settings.  Stored as ring buffer.
  DrawLib.TsunamiDrawCalculatorSettings[MAX_CARDINALITY] drawSettings;

  // need to store currentIndex and actual cardinality
  struct DrawSettingsRingBuffer {
    uint32 lastDrawId;
    uint32 nextIndex;
    uint32 cardinality;
  }

  DrawSettingsRingBuffer internal ringBuffer;

  /* ============ Constructor ============ */

  ///@notice Constructor for TsunamiDrawCalculator
  ///@param _ticket Ticket associated with this DrawCalculator
  ///@param _drawSettingsManager Address of the DrawSettingsManager. Can be different from the contract owner.
  constructor(ITicket _ticket, address _drawSettingsManager, uint32 _cardinality) {
    require(_cardinality <= MAX_CARDINALITY, "DrawCalc/card-lte-max");
    require(address(_ticket) != address(0), "DrawCalc/ticket-not-zero");
    ringBuffer.cardinality = _cardinality;
    setManager(_drawSettingsManager);
    ticket = _ticket;

    emit Deployed(_ticket);
  }

  /* ============ External Functions ============ */

  ///@notice Calulates the prize amount for a user for Multiple Draws. Typically called by a ClaimableDraw.
  ///@param _user User for which to calcualte prize amount
  ///@param _draws draw array for which to calculate prize amounts for
  ///@param _pickIndicesForDraws The encoded pick indices for all Draws. Expected to be just indices of winning claims. Populated values must be less than totalUserPicks.
  ///@return An array of amount of prizes awardable
  function calculate(address _user, DrawLib.Draw[] calldata _draws, bytes calldata _pickIndicesForDraws)
    external override view returns (uint256[] memory)
  {

    uint256[][] memory pickIndices = abi.decode(_pickIndicesForDraws, (uint256 [][]));
    require(pickIndices.length == _draws.length, "DrawCalc/invalid-pick-indices-length");

    //now unpack Draw struct
    uint32[] memory _timestamps = new uint32[](_draws.length);
    uint256[] memory _winningRandomNumbers = new uint256[](_draws.length);

    for(uint256 i = 0; i < _draws.length; i++){
      _timestamps[i] = _draws[i].timestamp;
      _winningRandomNumbers[i] = _draws[i].winningRandomNumber;
    }

    DrawSettingsRingBuffer memory _ringBuffer = ringBuffer;

    DrawLib.TsunamiDrawCalculatorSettings[] memory _drawSettings =  new DrawLib.TsunamiDrawCalculatorSettings[](_draws.length);
    for(uint256 i = 0; i < _draws.length; i++){
      _drawSettings[i] = _getDrawSettings(_ringBuffer, _draws[i].drawId);
    }

    uint256[] memory userBalances = _getNormalizedBalancesAt(_user, _timestamps, _drawSettings);
    bytes32 _userRandomNumber = keccak256(abi.encodePacked(_user)); // hash the users address

    return _calculatePrizesAwardable(userBalances, _userRandomNumber, _winningRandomNumbers, pickIndices, _drawSettings);
  }

  ///@notice Sets TsunamiDrawCalculatorSettings for a draw id. only callable by the owner or manager
  ///@param _drawId The id of the Draw
  ///@param _drawSettings The TsunamiDrawCalculatorSettings to set
  function pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawCalculatorSettings calldata _drawSettings) external onlyManagerOrOwner
    returns (bool success) 
  {
    return _pushDrawSettings(_drawId, _drawSettings);
  }

  ///@notice Gets the TsunamiDrawCalculatorSettings for a draw id
  ///@param _drawId The id of the Draw
  function getDrawSettings(uint32 _drawId) external view returns(DrawLib.TsunamiDrawCalculatorSettings memory)
  {
    return _getDrawSettings(ringBuffer, _drawId);
  }

  /* ============ Internal Functions ============ */

  ///@notice Calculates the prizes awardable foe each Draw passed. Called by calculate()
  ///@param _normalizedUserBalances Number of picks the user has for each Draw
  ///@param _userRandomNumber Random number of the user to consider over draws
  ///@param _winningRandomNumbers Winning random numbers for each Draw
  ///@param _pickIndicesForDraws Pick indices for each Draw
  ///@param _drawSettings TsunamiDrawCalculatorSettings for each Draw
  function _calculatePrizesAwardable(uint256[] memory _normalizedUserBalances, bytes32 _userRandomNumber,
    uint256[] memory _winningRandomNumbers, uint256[][] memory _pickIndicesForDraws, DrawLib.TsunamiDrawCalculatorSettings[] memory _drawSettings)
    internal view returns (uint256[] memory)
   {

    uint256[] memory prizesAwardable = new uint256[](_normalizedUserBalances.length);
    // calculate prizes awardable for each Draw passed
    for (uint32 drawIndex = 0; drawIndex < _winningRandomNumbers.length; drawIndex++) {
      uint256 totalUserPicks = _calculateNumberOfUserPicks(_drawSettings[drawIndex], _normalizedUserBalances[drawIndex]);
      prizesAwardable[drawIndex] = _calculate(_winningRandomNumbers[drawIndex], totalUserPicks, _userRandomNumber, _pickIndicesForDraws[drawIndex], _drawSettings[drawIndex]);
    }
    return prizesAwardable;
  }

  ///@notice Calculates the number of picks a user gets for a Draw, considering the normalized user balance and the draw settings
  ///@dev Divided by 1e18 since the normalized user balance is stored as a base 18 number
  ///@param _drawSettings The TsunamiDrawCalculatorSettings to consider
  ///@param _normalizedUserBalance The normalized user balances to consider
  function _calculateNumberOfUserPicks(DrawLib.TsunamiDrawCalculatorSettings memory _drawSettings, uint256 _normalizedUserBalance) internal view returns (uint256) {
    return (_normalizedUserBalance * _drawSettings.numberOfPicks) / 1 ether;
  }

  ///@notice Calculates the normalized balance of a user against the total supply for timestamps
  ///@param _user The user to consider
  ///@param _timestamps The timestamps to consider
  ///@param _drawSettings The draw settings to consider (needed for draw timstamp offsets)
  ///@return An array of normalized balances
  function _getNormalizedBalancesAt(address _user, uint32[] memory _timestamps, DrawLib.TsunamiDrawCalculatorSettings[] memory _drawSettings) internal view returns (uint256[] memory) {
    uint32[] memory _timestampsWithStartCutoffTimes = new uint32[](_timestamps.length);
    uint32[] memory _timestampsWithEndCutoffTimes = new uint32[](_timestamps.length);

    // generate timestamps with draw cutoff offsets included
    for (uint32 i = 0; i < _timestamps.length; i++) {
      _timestampsWithStartCutoffTimes[i] = _timestamps[i] - _drawSettings[i].drawStartTimestampOffset;
      _timestampsWithEndCutoffTimes[i] = _timestamps[i] - _drawSettings[i].drawEndTimestampOffset;
    }

    uint256[] memory balances = ticket.getAverageBalancesBetween(_user, _timestampsWithStartCutoffTimes, _timestampsWithEndCutoffTimes);
    uint256[] memory totalSupplies = ticket.getAverageTotalSuppliesBetween(_timestampsWithStartCutoffTimes, _timestampsWithEndCutoffTimes);

    uint256[] memory normalizedBalances = new uint256[](_timestamps.length);

    // divide balances by total supplies (normalize)
    for (uint256 i = 0; i < _timestamps.length; i++) {
      require(totalSupplies[i] > 0, "DrawCalc/total-supply-zero");
      normalizedBalances[i] = balances[i] * 1 ether / totalSupplies[i];
    }

    return normalizedBalances;
  }


  ///@notice calculates the prize amount per Draw per users pick
  ///@param _winningRandomNumber The Draw's winningRandomNumber
  ///@param totalUserPicks The number of picks the user gets for the Draw
  ///@param _userRandomNumber the users randomNumber for that draw
  ///@param _picks The users picks for that draw
  ///@param _drawSettings Params with the associated draw
  ///@return prize (if any) per Draw claim
  function _calculate(uint256 _winningRandomNumber, uint256 totalUserPicks, bytes32 _userRandomNumber, uint256[] memory _picks, DrawLib.TsunamiDrawCalculatorSettings memory _drawSettings)
    internal view returns (uint256)
  {

    uint256[] memory prizeCounts =  new uint256[](_drawSettings.distributions.length);
    uint256[] memory masks =  _createBitMasks(_drawSettings);
    uint256 picksLength = _picks.length;

    require(picksLength <= _drawSettings.maxPicksPerUser, "DrawCalc/exceeds-max-user-picks");

    // for each pick find number of matching numbers and calculate prize distribution index
    for(uint256 index  = 0; index < picksLength; index++){
      // hash the user random number with the pick index
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(_userRandomNumber, _picks[index])));
      require(_picks[index] < totalUserPicks, "DrawCalc/insufficient-user-picks");

      uint256 distributionIndex =  _calculateDistributionIndex(randomNumberThisPick, _winningRandomNumber, masks);

      if(distributionIndex < _drawSettings.distributions.length) { // there is prize for this distribution index
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
    return (prizeFraction * _drawSettings.prize) / 1e9; // div by 1e9 as prize distributions are base 1e9
  }

  ///@notice Calculates the distribution index given the random numbers and masks
  ///@param _randomNumberThisPick users random number for this Pick
  ///@param _winningRandomNumber The winning number for this draw
  ///@param _masks The pre-calculate bitmasks for the drawSettings
  ///@return The position within the prize distribution array (0 = top prize, 1 = runner-up prize, etc)
  function _calculateDistributionIndex(uint256 _randomNumberThisPick, uint256 _winningRandomNumber, uint256[] memory _masks)
    internal pure returns (uint256)
  {

    uint256 numberOfMatches = 0;
    uint256 masksLength = _masks.length;

    for(uint256 matchIndex = 0; matchIndex < masksLength; matchIndex++) {
      uint256 mask = _masks[matchIndex];
      if((_randomNumberThisPick & mask) != (_winningRandomNumber & mask)){
        // there are no more sequential matches since this comparison is not a match
        return masksLength - numberOfMatches;
      }
      // else there was a match
      numberOfMatches++;
    }
    return masksLength - numberOfMatches;
  }


  ///@notice helper function to create bitmasks equal to the matchCardinality
  ///@param _drawSettings The TsunamiDrawCalculatorSettings to use to calculate the masks
  ///@return An array of bitmasks
  function _createBitMasks(DrawLib.TsunamiDrawCalculatorSettings memory _drawSettings)
    internal pure returns (uint256[] memory)
  {
    uint256[] memory masks = new uint256[](_drawSettings.matchCardinality);

    uint256 _bitRangeMaskValue = (2 ** _drawSettings.bitRangeSize) - 1; // get a decimal representation of bitRangeSize

    for(uint256 maskIndex = 0; maskIndex < _drawSettings.matchCardinality; maskIndex++){
      uint16 _matchIndexOffset = uint16(maskIndex * _drawSettings.bitRangeSize);
      masks[maskIndex] = _bitRangeMaskValue << _matchIndexOffset;
    }

    return masks;
  }

  ///@notice Calculates the expected prize fraction per TsunamiDrawCalculatorSettings and prizeDistributionIndex
  ///@param _drawSettings TsunamiDrawCalculatorSettings struct for Draw
  ///@param _prizeDistributionIndex Index of the prize distribution array to calculate
  ///@return returns the fraction of the total prize (base 1e18)
  function _calculatePrizeDistributionFraction(DrawLib.TsunamiDrawCalculatorSettings memory _drawSettings, uint256 _prizeDistributionIndex) internal pure returns (uint256)
  {
    uint256 prizeDistribution = _drawSettings.distributions[_prizeDistributionIndex];
    uint256 numberOfPrizesForIndex = _numberOfPrizesForIndex(_drawSettings.bitRangeSize, _prizeDistributionIndex);
    return prizeDistribution / numberOfPrizesForIndex;
  }

  ///@notice Calculates the number of prizes for a given prizeDistributionIndex
  ///@param _bitRangeSize TsunamiDrawCalculatorSettings struct for Draw
  ///@param _prizeDistributionIndex Index of the prize distribution array to calculate
  ///@return returns the fraction of the total prize (base 1e18)
  function _numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeDistributionIndex) internal pure returns (uint256) {
    uint256 bitRangeDecimal = 2 ** uint256(_bitRangeSize);
    uint256 numberOfPrizesForIndex = bitRangeDecimal ** _prizeDistributionIndex;

    if(_prizeDistributionIndex > 0){
      numberOfPrizesForIndex -= bitRangeDecimal ** (_prizeDistributionIndex - 1);
    }
    return numberOfPrizesForIndex;
  }

  ///@notice Set the DrawCalculators TsunamiDrawCalculatorSettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param _drawId The id of the Draw
  ///@param _drawSettings TsunamiDrawCalculatorSettings struct to set
  function _pushDrawSettings(uint32 _drawId, DrawLib.TsunamiDrawCalculatorSettings calldata _drawSettings) internal
    returns (bool)
  {
    uint256 distributionsLength = _drawSettings.distributions.length;

    require(_drawSettings.matchCardinality >= distributionsLength, "DrawCalc/matchCardinality-gte-distributions");
    require(_drawSettings.bitRangeSize <= 256 / _drawSettings.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_drawSettings.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
    require(_drawSettings.numberOfPicks > 0, "DrawCalc/numberOfPicks-gt-0");
    require(_drawSettings.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");

    // ensure that the distributions are not gt 100%
    uint256 sumTotalDistributions = 0;
    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    }

    require(sumTotalDistributions <= 1e9, "DrawCalc/distributions-gt-100%");

    DrawSettingsRingBuffer memory _ringBuffer = ringBuffer;

    require((_ringBuffer.nextIndex == 0 && _ringBuffer.lastDrawId == 0) || _drawId == _ringBuffer.lastDrawId + 1, "DrawCalc/must-be-contig");
    drawSettings[_ringBuffer.nextIndex] = _drawSettings;
    _ringBuffer.nextIndex = uint32(RingBuffer.nextIndex(_ringBuffer.nextIndex, _ringBuffer.cardinality));
    _ringBuffer.lastDrawId = _drawId;

    ringBuffer = _ringBuffer;

    emit DrawSettingsSet(_drawId, _drawSettings);
    return true;
  }

  function _getDrawSettings(DrawSettingsRingBuffer memory _ringBuffer, uint32 drawId) internal view returns (DrawLib.TsunamiDrawCalculatorSettings memory) {
    require(drawId <= _ringBuffer.lastDrawId, "DrawCalc/future-draw");
    uint32 indexOffset = _ringBuffer.lastDrawId - drawId;
    require(indexOffset < _ringBuffer.cardinality, "DrawCalc/expired-draw");
    uint32 mostRecent = uint32(RingBuffer.mostRecentIndex(_ringBuffer.nextIndex, _ringBuffer.cardinality));
    uint32 index = uint32(RingBuffer.offset(mostRecent, indexOffset, _ringBuffer.cardinality));
    return drawSettings[index];
  }
}
