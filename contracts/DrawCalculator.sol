// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/Ownable.sol";
import "./DrawPrizes.sol";
import "./PrizeDistributionHistory.sol";
import "./interfaces/IDrawCalculator.sol";
import "./interfaces/ITicket.sol";
import "./interfaces/IDrawHistory.sol";
import "./libraries/DrawLib.sol";
import "./libraries/DrawRingBufferLib.sol";



/**
  * @title  PoolTogether V4 DrawCalculator
  * @author PoolTogether Inc Team
  * @notice The DrawCalculator calculates a user's prize by matching a winning random number against
            their picks. A users picks are generated deterministically based on their address and balance
            of tickets held. Prize payouts are divided into multiple tiers: grand prize, second place, etc... 
            A user with a higher average weighted balance (during each draw perid) will be given a large number of
            pickIndices to choose from, and thus a higher chance to match the randomly generated winning numbers. 
            The DrawCalculator will retrieve data, like average weighted balance and cost of picks per draw 
            from the linked Ticket and PrizeDistributionHistory contracts when payouts are being calculated. 
*/
contract DrawCalculator is IDrawCalculator, Ownable {

  /**
    * @notice Emitted when a global DrawHistory variable is set.
    * @param drawHistory DrawHistory address
  */
  event DrawHistorySet (
    IDrawHistory indexed drawHistory
  );


  /// @notice DrawHistory address
  IDrawHistory internal drawHistory;

  /// @notice Ticket associated with DrawCalculator
  ITicket immutable ticket;

  /// @notice The stored history of draw settings.  Stored as ring buffer.
  PrizeDistributionHistory immutable prizeDistributionHistory;

  /// @notice The distributions array length
  uint8 public constant DISTRIBUTIONS_LENGTH = 16;

  /* ============ Constructor ============ */

  /// @notice Constructor for DrawCalculator
  /// @param _owner Address of the DrawCalculator owner
  /// @param _ticket Ticket associated with this DrawCalculator
  /// @param _drawHistory The address of the draw history to push draws to
  /// @param _prizeDistributionHistory PrizeDistributionHistory address
  constructor(
    address _owner,
    ITicket _ticket,
    IDrawHistory _drawHistory,
    PrizeDistributionHistory _prizeDistributionHistory
  ) Ownable(_owner) {
    require(address(_ticket) != address(0), "DrawCalc/ticket-not-zero");
    require(address(_prizeDistributionHistory) != address(0), "DrawCalc/tdsh-not-zero");
    _setDrawHistory(_drawHistory);
    prizeDistributionHistory = _prizeDistributionHistory;
    ticket = _ticket;

    emit Deployed(_ticket);
  }

  /* ============ External Functions ============ */

  /// @inheritdoc IDrawCalculator
  function calculate(
    address _user, uint32[] calldata _drawIds, 
    bytes calldata _pickIndicesForDraws
  ) external override view returns (uint256[] memory) {
    
    uint64[][] memory pickIndices = abi.decode(_pickIndicesForDraws, (uint64 [][]));
    require(pickIndices.length == _drawIds.length, "DrawCalc/invalid-pick-indices-length");


    // READ list of DrawLib.Draw using the Draw.drawId[] 
    DrawLib.Draw[] memory draws = drawHistory.getDraws(_drawIds);

    // READ list of DrawLib.PrizeDistribution using the Draw.drawId[]
    DrawLib.PrizeDistribution[] memory _drawSettings = prizeDistributionHistory.getDrawSettings(_drawIds);

    /**
      * Maximum number of picks per user is calculated by getting a Ticket time-weighted average balance (TWAB).
      * Using a Draw.timestamp + DrawSetings.endOffsetTimestamp a list of balances held (on average) by a User
      * can be read via the Ticket contract. The TWAB determines a maximum number of picks per user, per draw.
     */
    uint256[] memory userBalances = _getNormalizedBalancesAt(_user, draws, _drawSettings);

    /**
      * The userRandomNumber is currently generated via hashing the user address.
      * In future iterations of DrawCalculator the userRandomNumber could be set using
      * input params supplied by the user. Giving users "agency" to select what
      * random numbers are generated each beacon complete draw period. 
     */
    bytes32 _userRandomNumber = keccak256(abi.encodePacked(_user));

    /**
      * The time weighted average balances peraining to each Draw period is supplied will be returned a User balances list.
      * A list of prize amounts that can be claimed by supplied user address is returned.
     */
    return _calculatePrizesAwardable(userBalances, _userRandomNumber, draws, pickIndices, _drawSettings);
  }

  /// @inheritdoc IDrawCalculator
  function getDrawHistory() external view override returns (IDrawHistory) {
    return drawHistory;
  }

  /// @inheritdoc IDrawCalculator
  function getPrizeDistributionHistory() external view override returns (PrizeDistributionHistory) {
    return prizeDistributionHistory;
  }

  /// @inheritdoc IDrawCalculator
  function setDrawHistory(IDrawHistory _drawHistory) external override onlyOwner returns (IDrawHistory) {
    _setDrawHistory(_drawHistory);
    return _drawHistory;
  }

  /// @inheritdoc IDrawCalculator
  function getNormalizedBalancesForDrawIds(address _user, uint32[] calldata _drawIds) external view override returns (uint256[] memory) {
    DrawLib.Draw[] memory _draws = drawHistory.getDraws(_drawIds);
    DrawLib.PrizeDistribution[] memory _drawSettings = prizeDistributionHistory.getDrawSettings(_drawIds);
    return _getNormalizedBalancesAt(_user, _draws, _drawSettings);
  }

  /// @inheritdoc IDrawCalculator
  function checkPrizeDistributionIndicesForDrawId(
    address _user, 
    uint64[] calldata _pickIndices, 
    uint32 _drawId
  ) external view override returns(PickPrize[] memory) {
    uint32[] memory drawIds = new uint32[](1);
    drawIds[0] = _drawId;

    DrawLib.Draw[] memory _draws = drawHistory.getDraws(drawIds);
    DrawLib.PrizeDistribution[] memory _drawSettings = prizeDistributionHistory.getDrawSettings(drawIds);
    
    uint256[] memory userBalances = _getNormalizedBalancesAt(_user, _draws, _drawSettings);
    uint256 totalUserPicks = _calculateNumberOfUserPicks(_drawSettings[0], userBalances[0]);

    uint256[] memory masks =  _createBitMasks(_drawSettings[0]);
    PickPrize[] memory pickPrizes = new PickPrize[](_pickIndices.length);
    
    bytes32 _userRandomNumber = keccak256(abi.encodePacked(_user)); // hash the users address

    for(uint64 i = 0; i < _pickIndices.length; i++){
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(_userRandomNumber, _pickIndices[i])));
      require(_pickIndices[i] < totalUserPicks, "DrawCalc/insufficient-user-picks");

      uint256 distributionIndex =  _calculateDistributionIndex(randomNumberThisPick, _draws[0].winningRandomNumber, masks);

      pickPrizes[i] = PickPrize({
        won: distributionIndex < _drawSettings[0].distributions.length && _drawSettings[0].distributions[distributionIndex] > 0, 
        distributionIndex: uint8(distributionIndex)
      });
    }

    return pickPrizes;
  }

  /* ============ Internal Functions ============ */

  /**
    * @notice Set global DrawHistory reference.
    * @param _drawHistory DrawHistory address
  */
  function _setDrawHistory(IDrawHistory _drawHistory) internal {
    require(address(_drawHistory) != address(0), "DrawCalc/dh-not-zero");
    drawHistory = _drawHistory;
    emit DrawHistorySet(_drawHistory);
  }

  /**
    * @notice Calculates the prizes awardable foe each Draw passed. Called by calculate()
    * @param _normalizedUserBalances User TWABs for each draw settings perods
    * @param _userRandomNumber       Random number of the user to consider over draws
    * @param _draws                  Draws
    * @param _pickIndicesForDraws    Pick indices for each Draw
    * @param _drawSettings           DrawCalculatorSettings for each Draw
    * @return Awardable prizes list
  */
  function _calculatePrizesAwardable(
    uint256[] memory _normalizedUserBalances, 
    bytes32 _userRandomNumber,
    DrawLib.Draw[] memory _draws, 
    uint64[][] memory _pickIndicesForDraws, 
    DrawLib.PrizeDistribution[] memory _drawSettings
  ) internal view returns (uint256[] memory)
   {
    uint256[] memory prizesAwardable = new uint256[](_normalizedUserBalances.length);
    // calculate prizes awardable for each Draw passed
    for (uint32 drawIndex = 0; drawIndex < _draws.length; drawIndex++) {
      uint256 totalUserPicks = _calculateNumberOfUserPicks(_drawSettings[drawIndex], _normalizedUserBalances[drawIndex]);
      prizesAwardable[drawIndex] = _calculate(_draws[drawIndex].winningRandomNumber, totalUserPicks, _userRandomNumber, _pickIndicesForDraws[drawIndex], _drawSettings[drawIndex]);
    }
    return prizesAwardable;
  }
  /**
    * @notice Calculates the number of picks a user gets for a Draw, considering the normalized user balance and the draw settings
    * @dev Divided by 1e18 since the normalized user balance is stored as a base 18 number
    * @param _drawSettings The DrawCalculatorSettings to consider
    * @param _normalizedUserBalance The normalized user balances to consider
  */
  function _calculateNumberOfUserPicks(DrawLib.PrizeDistribution memory _drawSettings, uint256 _normalizedUserBalance) internal view returns (uint256) {
    return (_normalizedUserBalance * _drawSettings.numberOfPicks) / 1 ether;
  }

  /**
    * @notice Calculates the normalized balance of a user against the total supply for timestamps
    * @param _user The user to consider
    * @param _draws The draws we are looking at
    * @param _drawSettings The draw settings to consider (needed for draw timstamp offsets)
    * @return An array of normalized balances
  */
  function _getNormalizedBalancesAt(address _user, DrawLib.Draw[] memory _draws, DrawLib.PrizeDistribution[] memory _drawSettings) internal view returns (uint256[] memory) {
    uint32[] memory _timestampsWithStartCutoffTimes = new uint32[](_draws.length);
    uint32[] memory _timestampsWithEndCutoffTimes = new uint32[](_draws.length);

    // generate timestamps with draw cutoff offsets included
    for (uint32 i = 0; i < _draws.length; i++) {
      unchecked {
        _timestampsWithStartCutoffTimes[i] = uint32(_draws[i].timestamp - _drawSettings[i].startTimestampOffset);
        _timestampsWithEndCutoffTimes[i] = uint32(_draws[i].timestamp - _drawSettings[i].endTimestampOffset);
      }
    }

    uint256[] memory balances = ticket.getAverageBalancesBetween(_user, _timestampsWithStartCutoffTimes, _timestampsWithEndCutoffTimes);
    uint256[] memory totalSupplies = ticket.getAverageTotalSuppliesBetween(_timestampsWithStartCutoffTimes, _timestampsWithEndCutoffTimes);

    uint256[] memory normalizedBalances = new uint256[](_draws.length);

    // divide balances by total supplies (normalize)
    for (uint256 i = 0; i < _draws.length; i++) {
      require(totalSupplies[i] > 0, "DrawCalc/total-supply-zero");
      normalizedBalances[i] = balances[i] * 1 ether / totalSupplies[i];
    }

    return normalizedBalances;
  }

  /**
    * @notice calculates the prize amount per Draw per users pick
    * @param _winningRandomNumber The Draw's winningRandomNumber
    * @param _totalUserPicks      The number of picks the user gets for the Draw
    * @param _userRandomNumber    The users randomNumber for that draw
    * @param _picks               The users picks for that draw
    * @param _drawSettings        DrawLib.PrizeDistribution
    * @return prize (if any) per Draw claim
  */
  function _calculate(uint256 _winningRandomNumber, uint256 _totalUserPicks, bytes32 _userRandomNumber, uint64[] memory _picks, DrawLib.PrizeDistribution memory _drawSettings)
    internal view returns (uint256)
  {

    uint256[] memory prizeCounts =  new uint256[](_drawSettings.distributions.length);
    uint256[] memory masks =  _createBitMasks(_drawSettings);
    uint256 picksLength = _picks.length;

    uint8 maxWinningDistributionIndex = 0;

    require(picksLength <= _drawSettings.maxPicksPerUser, "DrawCalc/exceeds-max-user-picks");

    // for each pick find number of matching numbers and calculate prize distribution index
    for(uint64 index = 0; index < picksLength; index++){
      require(_picks[index] < _totalUserPicks, "DrawCalc/insufficient-user-picks");
      if(index > 0){
        require(_picks[index] > _picks[index - 1], "DrawCalc/picks-ascending");
      }    
      // hash the user random number with the pick index
      uint256 randomNumberThisPick = uint256(keccak256(abi.encode(_userRandomNumber, _picks[index])));
      uint8 distributionIndex =  _calculateDistributionIndex(randomNumberThisPick, _winningRandomNumber, masks);
      
      if(distributionIndex < DISTRIBUTIONS_LENGTH) { // there is prize for this distribution index
        if(distributionIndex > maxWinningDistributionIndex){
          maxWinningDistributionIndex = distributionIndex;
        }
        prizeCounts[distributionIndex]++;
      }
    }

    // now calculate prizeFraction given prize counts
    uint256 prizeFraction = 0;
    for(uint64 prizeCountIndex = 0; prizeCountIndex <= maxWinningDistributionIndex; prizeCountIndex++) {
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
    internal pure returns (uint8)
  {

    uint8 numberOfMatches = 0;
    uint8 masksLength = uint8(_masks.length);

    for(uint8 matchIndex = 0; matchIndex < masksLength; matchIndex++) {
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


  /**
    * @notice Create bitmasks equal to the DrawLib.PrizeDistribution.matchCardinality
    * @param _drawSettings The DrawCalculatorSettings to use to calculate the masks
    * @return An array of bitmasks
  */
  function _createBitMasks(DrawLib.PrizeDistribution memory _drawSettings)
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

  /**
    * @notice Calculates the expected prize fraction per DrawCalculatorSettings and prizeDistributionIndex
    * @param _drawSettings DrawCalculatorSettings struct for Draw
    * @param _prizeDistributionIndex Index of the prize distribution array to calculate
    * @return returns the fraction of the total prize (base 1e18)
  */
  function _calculatePrizeDistributionFraction(
    DrawLib.PrizeDistribution memory _drawSettings, 
    uint256 _prizeDistributionIndex
  ) internal pure returns (uint256) {
    uint256 prizeDistribution = _drawSettings.distributions[_prizeDistributionIndex];
    uint256 numberOfPrizesForIndex = _numberOfPrizesForIndex(_drawSettings.bitRangeSize, _prizeDistributionIndex);
    return prizeDistribution / numberOfPrizesForIndex;
  }


  /**
    * @notice Calculates the number of prizes for a given prizeDistributionIndex
    * @param _bitRangeSize DrawCalculatorSettings struct for Draw
    * @param _prizeDistributionIndex Index of the prize distribution array to calculate
    * @return returns the fraction of the total prize (base 1e18)
  */
  function _numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeDistributionIndex) internal pure returns (uint256) {
    uint256 bitRangeDecimal = 2 ** uint256(_bitRangeSize);
    uint256 numberOfPrizesForIndex = bitRangeDecimal ** _prizeDistributionIndex;

    if(_prizeDistributionIndex > 0){
      numberOfPrizesForIndex -= bitRangeDecimal ** (_prizeDistributionIndex - 1);
    }
    return numberOfPrizesForIndex;
  }
}
