// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicket.sol";
import "./ClaimableDraw.sol";
import "./libraries/DrawLib.sol";

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@pooltogether/owner-manager-contracts/contracts/OwnerOrManager.sol";


///@title TsunamiDrawCalculator is an implmentation of an IDrawCalculator
contract TsunamiDrawCalculator is IDrawCalculator, OwnerOrManager {
  
  ///@notice Ticket associated with DrawCalculator
  ITicket ticket;

  ///@notice ClaimableDraw associated with DrawCalculator
  ClaimableDraw public claimableDraw;

  ///@notice storage of the DrawSettings associated with a drawId
  mapping(uint32 => DrawLib.DrawSettings) drawSettings;

  /* ============ External Functions ============ */

  ///@notice Initializer sets the initial parameters
  ///@param _ticket Ticket associated with this DrawCalculator
  ///@param _drawSettingsManager Address of the DrawSettingsManager. Can be different from the contract owner.
  ///@param _claimableDraw ClaimableDraw associated with this DrawCalculator
  function initialize(ITicket _ticket, address _drawSettingsManager, ClaimableDraw _claimableDraw)
    public initializer
  {
    require(address(_ticket) != address(0), "DrawCalc/ticket-not-zero");
    __Ownable_init();
    setManager(_drawSettingsManager);
    _setClaimableDraw(_claimableDraw);
    ticket = _ticket;
    emit Initialized(_ticket);
  }

  ///@notice Calulates the prize amount for a user for Multiple Draws. Typically called by a ClaimableDraw.
  ///@param _user User for which to calcualte prize amount
  ///@param _draws draw array for which to calculate prize amounts for
  ///@param _pickIndicesForDraws The encoded pick indices for all Draws. Expected to be just indices of winning claims. Populated values must be less than totalUserPicks.
  ///@return An array of amount of prizes awardable
  function calculate(address _user, DrawLib.Draw[] calldata _draws, bytes calldata _pickIndicesForDraws)
    external override view returns (uint96[] memory)
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
    require(_timestamps.length == _winningRandomNumbers.length, "DrawCalc/invalid-draw-length");


    DrawLib.DrawSettings[] memory _drawSettings =  new DrawLib.DrawSettings[](_draws.length);
    for(uint256 i = 0; i < _draws.length; i++){
      _drawSettings[i] = drawSettings[_draws[i].drawId];
    }

    uint256[] memory userBalances = _getNormalizedBalancesAt(_user, _timestamps, _drawSettings);
    bytes32 _userRandomNumber = keccak256(abi.encodePacked(_user)); // hash the users address

    return _calculatePrizesAwardable(userBalances, _userRandomNumber, _winningRandomNumbers, pickIndices, _drawSettings);
  }

  ///@notice Sets DrawSettings for a draw id. only callable by the owner or manager
  ///@param _drawId The id of the Draw
  ///@param _drawSettings The DrawSettings to set
  function setDrawSettings(uint32 _drawId, DrawLib.DrawSettings calldata _drawSettings) external onlyManagerOrOwner
    returns (bool success) 
  {
    return _setDrawSettings(_drawId, _drawSettings);
  }

  ///@notice Sets DrawSettings for a draw id. only callable by the owner or manager
  ///@param _claimableDraw The address of the ClaimableDraw to update with the updated DrawSettings
  function setClaimableDraw(ClaimableDraw _claimableDraw) external onlyManagerOrOwner returns(ClaimableDraw)
  {
    return _setClaimableDraw(_claimableDraw);
  }

  ///@notice Gets the DrawSettings for a draw id
  ///@param _drawId The id of the Draw
  function getDrawSettings(uint32 _drawId) external view returns(DrawLib.DrawSettings memory)
  {
    DrawLib.DrawSettings memory _drawSettings = drawSettings[_drawId];
    return _drawSettings;
  }
  
  /* ============ Internal Functions ============ */

  ///@notice Calculates the prizes awardable foe each Draw passed. Called by calculate()
  ///@param _normalizedUserBalances Number of picks the user has for each Draw
  ///@param _userRandomNumber Random number of the user to consider over draws
  ///@param _winningRandomNumbers Winning random numbers for each Draw
  ///@param _pickIndicesForDraws Pick indices for each Draw
  ///@param _drawSettings DrawSettings for each Draw
  function _calculatePrizesAwardable(uint256[] memory _normalizedUserBalances, bytes32 _userRandomNumber,
    uint256[] memory _winningRandomNumbers, uint256[][] memory _pickIndicesForDraws, DrawLib.DrawSettings[] memory _drawSettings)
    internal view returns (uint96[] memory)
   {

    uint96[] memory prizesAwardable = new uint96[](_normalizedUserBalances.length);
    
    // calculate prizes awardable for each Draw passed
    for (uint32 drawIndex = 0; drawIndex < _winningRandomNumbers.length; drawIndex++) {
      uint256 totalUserPicks = _calculateNumberOfUserPicks(_drawSettings[drawIndex], _normalizedUserBalances[drawIndex]);
      prizesAwardable[drawIndex] = _calculate(_winningRandomNumbers[drawIndex], totalUserPicks, _userRandomNumber, _pickIndicesForDraws[drawIndex], _drawSettings[drawIndex]);
    }
    return prizesAwardable;
  }

  ///@notice Calculates the number of picks a user gets for a Draw, considering the normalized user balance and the draw settings
  ///@dev Divided by 1e18 since the normalized user balance is stored as a base 18 number
  ///@param _drawSettings The DrawSettings to consider
  ///@param _normalizedUserBalance The normalized user balances to consider
  function _calculateNumberOfUserPicks(DrawLib.DrawSettings memory _drawSettings, uint256 _normalizedUserBalance) internal view returns (uint256) {
    return (_normalizedUserBalance * _drawSettings.numberOfPicks) / 1 ether;
  }

  ///@notice Calculates the normalized balance of a user against the total supply for timestamps
  ///@param _user The user to consider
  ///@param _timestamps The timestamps to consider
  ///@param _drawSettings The draw settings to consider (needed for draw timstamp offsets)
  ///@return An array of normalized balances
  function _getNormalizedBalancesAt(address _user, uint32[] memory _timestamps, DrawLib.DrawSettings[] memory _drawSettings) internal view returns (uint256[] memory) {
    
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
  function _calculate(uint256 _winningRandomNumber, uint256 totalUserPicks, bytes32 _userRandomNumber, uint256[] memory _picks, DrawLib.DrawSettings memory _drawSettings)
    internal view returns (uint96)
  {
    
    uint256[] memory prizeCounts =  new uint256[](_drawSettings.distributions.length);
    uint256[] memory masks =  _createBitMasks(_drawSettings);
    uint256 picksLength = _picks.length;

    // console.log("picksLength ", picksLength);
    // console.log("picksLength ", picksLength);
    
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
    return uint96((prizeFraction * _drawSettings.prize) / 1e18); // div by 1 ether as prize distributions are base 1e18
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
  ///@param _drawSettings The DrawSettings to use to calculate the masks
  ///@return An array of bitmasks
  function _createBitMasks(DrawLib.DrawSettings memory _drawSettings) 
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

  ///@notice Calculates the expected prize fraction per DrawSettings and prizeDistributionIndex
  ///@param _drawSettings DrawSettings struct for Draw
  ///@param _prizeDistributionIndex Index of the prize distribution array to calculate
  ///@return returns the fraction of the total prize (base 1e18)
  function _calculatePrizeDistributionFraction(DrawLib.DrawSettings memory _drawSettings, uint256 _prizeDistributionIndex) internal pure returns (uint256) 
  {
    uint256 prizeDistribution = _drawSettings.distributions[_prizeDistributionIndex];
    uint256 numberOfPrizesForIndex = _numberOfPrizesForIndex(_drawSettings.bitRangeSize, _prizeDistributionIndex);
    return prizeDistribution / numberOfPrizesForIndex;
  }

  ///@notice Calculates the number of prizes for a given prizeDistributionIndex
  ///@param _bitRangeSize DrawSettings struct for Draw
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

  ///@notice Set the DrawCalculators DrawSettings
  ///@dev Distributions must be expressed with Ether decimals (1e18)
  ///@param drawId The id of the Draw
  ///@param _drawSettings DrawSettings struct to set
  function _setDrawSettings(uint32 drawId, DrawLib.DrawSettings calldata _drawSettings) internal
    returns (bool)
  {
    uint256 sumTotalDistributions = 0;
    uint256 distributionsLength = _drawSettings.distributions.length;

    require(_drawSettings.matchCardinality >= distributionsLength, "DrawCalc/matchCardinality-gt-distributions");
    require(_drawSettings.bitRangeSize <= 256 / _drawSettings.matchCardinality, "DrawCalc/bitRangeSize-too-large");
    require(_drawSettings.bitRangeSize > 0, "DrawCalc/bitRangeSize-gt-0");
    require(_drawSettings.numberOfPicks > 0, "DrawCalc/numberOfPicks-gt-0");
    require(_drawSettings.maxPicksPerUser > 0, "DrawCalc/maxPicksPerUser-gt-0");
    
    // ensure that the distributions are not gt 100%
    for(uint256 index = 0; index < distributionsLength; index++){
      sumTotalDistributions += _drawSettings.distributions[index];
    }

    require(sumTotalDistributions <= 1 ether, "DrawCalc/distributions-gt-100%");

    claimableDraw.setDrawCalculator(drawId, IDrawCalculator(address(this)));

    drawSettings[drawId] = _drawSettings; //sstore
    emit DrawSettingsSet(drawId, _drawSettings);
    return true;
  }

  ///@notice Internal function to set the Claimable Draw address
  ///@param _claimableDraw The address of the Claimable Draw contract to set
  function _setClaimableDraw(ClaimableDraw _claimableDraw) internal returns(ClaimableDraw)
  {
    require(address(_claimableDraw) != address(0), "DrawCalc/claimable-draw-not-zero-address");
    claimableDraw = _claimableDraw;
    emit ClaimableDrawSet(_claimableDraw);
    return _claimableDraw; 
  }

}
