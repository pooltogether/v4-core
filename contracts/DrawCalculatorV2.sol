// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./interfaces/ITicket.sol";
import "./interfaces/IDrawBuffer.sol";
import "./interfaces/IPrizeDistributionSource.sol";
import "./interfaces/IDrawBeacon.sol";

import "./PrizeDistributor.sol";

/**
  * @title  PoolTogether V4 DrawCalculatorV2
  * @author PoolTogether Inc Team
  * @notice The DrawCalculator calculates a user's prize by matching a winning random number against
            their picks. A users picks are generated deterministically based on their address and balance
            of tickets held. Prize payouts are divided into multiple tiers: grand prize, second place, etc...
            A user with a higher average weighted balance (during each draw period) will be given a large number of
            picks to choose from, and thus a higher chance to match the winning numbers.
*/
contract DrawCalculatorV2 {
    /* ============ Variables ============ */

    /// @notice DrawBuffer address
    IDrawBuffer public immutable drawBuffer;

    /// @notice Ticket associated with DrawCalculator
    ITicket public immutable ticket;

    /// @notice The source in which the history of draw settings are stored as ring buffer.
    IPrizeDistributionSource public immutable prizeDistributionSource;

    /// @notice The tiers array length
    uint8 public constant TIERS_LENGTH = 16;

    /* ============ Events ============ */

    ///@notice Emitted when the contract is initialized
    event Deployed(
        ITicket indexed ticket,
        IDrawBuffer indexed drawBuffer,
        IPrizeDistributionSource indexed prizeDistributionSource
    );

    ///@notice Emitted when the prizeDistributor is set/updated
    event PrizeDistributorSet(PrizeDistributor indexed prizeDistributor);

    /* ============ Constructor ============ */

    /**
     * @notice Constructor for DrawCalculator
     * @param _ticket Ticket associated with this DrawCalculator
     * @param _drawBuffer The address of the draw buffer to push draws to
     * @param _prizeDistributionSource PrizeDistributionSource address
    */
    constructor(
        ITicket _ticket,
        IDrawBuffer _drawBuffer,
        IPrizeDistributionSource _prizeDistributionSource
    ) {
        require(address(_ticket) != address(0), "DrawCalc/ticket-not-zero");
        require(address(_prizeDistributionSource) != address(0), "DrawCalc/pdb-not-zero");
        require(address(_drawBuffer) != address(0), "DrawCalc/dh-not-zero");

        ticket = _ticket;
        drawBuffer = _drawBuffer;
        prizeDistributionSource = _prizeDistributionSource;

        emit Deployed(_ticket, _drawBuffer, _prizeDistributionSource);
    }

    /* ============ External Functions ============ */

    /**
     * @notice Calculates the prize amount for a user for Multiple Draws. Typically called by a PrizeDistributor.
     * @param _user User for which to calculate prize amount.
     * @param _drawIds drawId array for which to calculate prize amounts for.
     * @param _pickIndicesForDraws The ABI encoded pick indices for all Draws. Expected to be winning picks. Pick indices must be less than the totalUserPicks.
     * @return List of awardable prize amounts ordered by drawId.
    */
    function calculate(
        address _user,
        uint32[] calldata _drawIds,
        bytes calldata _pickIndicesForDraws
    ) external view returns (uint256[] memory, bytes memory) {
        uint64[][] memory pickIndices = abi.decode(_pickIndicesForDraws, (uint64 [][]));
        require(pickIndices.length == _drawIds.length, "DrawCalc/invalid-pick-indices-length");

        // READ list of IDrawBeacon.Draw using the drawIds from drawBuffer
        IDrawBeacon.Draw[] memory draws = drawBuffer.getDraws(_drawIds);

        // READ list of IPrizeDistributionSource.PrizeDistribution using the drawIds
        IPrizeDistributionSource.PrizeDistribution[] memory _prizeDistributions = prizeDistributionSource
            .getPrizeDistributions(_drawIds);

        // The userBalances are fractions representing their portion of the liquidity for a draw.
        uint256[] memory userBalances = _getNormalizedBalancesAt(_user, draws, _prizeDistributions);

        // The users address is hashed once.
        bytes32 _userRandomNumber = keccak256(abi.encodePacked(_user));

        return _calculatePrizesAwardable(
                userBalances,
                _userRandomNumber,
                draws,
                pickIndices,
                _prizeDistributions
            );
    }

    /**
     * @notice Read global DrawBuffer variable.
     * @return IDrawBuffer
    */
    function getDrawBuffer() external view returns (IDrawBuffer) {
        return drawBuffer;
    }

    /**
     * @notice Read global prizeDistributionSource variable.
     * @return IPrizeDistributionSource
    */
    function getPrizeDistributionSource()
        external
        view
        returns (IPrizeDistributionSource)
    {
        return prizeDistributionSource;
    }

    /**
     * @notice Returns a users balances expressed as a fraction of the total supply over time.
     * @param _user The users address
     * @param _drawIds The drawIds to consider
     * @return Array of balances
    */
    function getNormalizedBalancesForDrawIds(address _user, uint32[] calldata _drawIds)
        external
        view
        returns (uint256[] memory)
    {
        IDrawBeacon.Draw[] memory _draws = drawBuffer.getDraws(_drawIds);
        IPrizeDistributionSource.PrizeDistribution[] memory _prizeDistributions = prizeDistributionSource
            .getPrizeDistributions(_drawIds);

        return _getNormalizedBalancesAt(_user, _draws, _prizeDistributions);
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Calculates the prizes awardable for each Draw passed.
     * @param _normalizedUserBalances Fractions representing the user's portion of the liquidity for each draw.
     * @param _userRandomNumber       Random number of the user to consider over draws
     * @param _draws                  List of Draws
     * @param _pickIndicesForDraws    Pick indices for each Draw
     * @param _prizeDistributions     PrizeDistribution for each Draw

     */
    function _calculatePrizesAwardable(
        uint256[] memory _normalizedUserBalances,
        bytes32 _userRandomNumber,
        IDrawBeacon.Draw[] memory _draws,
        uint64[][] memory _pickIndicesForDraws,
        IPrizeDistributionSource.PrizeDistribution[] memory _prizeDistributions
    ) internal view returns (uint256[] memory prizesAwardable, bytes memory prizeCounts) {

        uint256[] memory _prizesAwardable = new uint256[](_normalizedUserBalances.length);
        uint256[][] memory _prizeCounts = new uint256[][](_normalizedUserBalances.length);

        uint64 timeNow = uint64(block.timestamp);

        // calculate prizes awardable for each Draw passed
        for (uint32 drawIndex = 0; drawIndex < _draws.length; drawIndex++) {
            require(timeNow < _draws[drawIndex].timestamp + _prizeDistributions[drawIndex].expiryDuration, "DrawCalc/draw-expired");

            uint64 totalUserPicks = _calculateNumberOfUserPicks(
                _prizeDistributions[drawIndex],
                _normalizedUserBalances[drawIndex]
            );

            (_prizesAwardable[drawIndex], _prizeCounts[drawIndex]) = _calculate(
                _draws[drawIndex].winningRandomNumber,
                totalUserPicks,
                _userRandomNumber,
                _pickIndicesForDraws[drawIndex],
                _prizeDistributions[drawIndex]
            );
        }

        prizeCounts = abi.encode(_prizeCounts);
        prizesAwardable = _prizesAwardable;
    }

    /**
     * @notice Calculates the number of picks a user gets for a Draw, considering the normalized user balance and the PrizeDistribution.
     * @dev Divided by 1e18 since the normalized user balance is stored as a fixed point 18 number
     * @param _prizeDistribution The PrizeDistribution to consider
     * @param _normalizedUserBalance The normalized user balances to consider
     * @return The number of picks a user gets for a Draw
     */
    function _calculateNumberOfUserPicks(
        IPrizeDistributionSource.PrizeDistribution memory _prizeDistribution,
        uint256 _normalizedUserBalance
    ) internal pure returns (uint64) {
        return uint64((_normalizedUserBalance * _prizeDistribution.numberOfPicks) / 1 ether);
    }

    /**
     * @notice Calculates the normalized balance of a user against the total supply for timestamps
     * @param _user The user to consider
     * @param _draws The draws we are looking at
     * @param _prizeDistributions The prize tiers to consider (needed for draw timestamp offsets)
     * @return An array of normalized balances
     */
    function _getNormalizedBalancesAt(
        address _user,
        IDrawBeacon.Draw[] memory _draws,
        IPrizeDistributionSource.PrizeDistribution[] memory _prizeDistributions
    ) internal view returns (uint256[] memory) {
        uint256 drawsLength = _draws.length;
        uint64[] memory _timestampsWithStartCutoffTimes = new uint64[](drawsLength);
        uint64[] memory _timestampsWithEndCutoffTimes = new uint64[](drawsLength);

        // generate timestamps with draw cutoff offsets included
        for (uint32 i = 0; i < drawsLength; i++) {
            unchecked {
                _timestampsWithStartCutoffTimes[i] =
                    _draws[i].timestamp - _prizeDistributions[i].startTimestampOffset;
                _timestampsWithEndCutoffTimes[i] =
                    _draws[i].timestamp - _prizeDistributions[i].endTimestampOffset;
            }
        }

        uint256[] memory balances = ticket.getAverageBalancesBetween(
            _user,
            _timestampsWithStartCutoffTimes,
            _timestampsWithEndCutoffTimes
        );

        uint256[] memory totalSupplies = ticket.getAverageTotalSuppliesBetween(
            _timestampsWithStartCutoffTimes,
            _timestampsWithEndCutoffTimes
        );

        uint256[] memory normalizedBalances = new uint256[](drawsLength);

        // divide balances by total supplies (normalize)
        for (uint256 i = 0; i < drawsLength; i++) {
            if(totalSupplies[i] == 0){
                normalizedBalances[i] = 0;
            }
            else {
                normalizedBalances[i] = (balances[i] * 1 ether) / totalSupplies[i];
            }
        }

        return normalizedBalances;
    }

    /**
     * @notice Calculates the prize amount for a PrizeDistribution over given picks
     * @param _winningRandomNumber Draw's winningRandomNumber
     * @param _totalUserPicks      number of picks the user gets for the Draw
     * @param _userRandomNumber    users randomNumber for that draw
     * @param _picks               users picks for that draw
     * @param _prizeDistribution   PrizeDistribution for that draw
     * @return prize (if any), prizeCounts (if any)
     */
    function _calculate(
        uint256 _winningRandomNumber,
        uint256 _totalUserPicks,
        bytes32 _userRandomNumber,
        uint64[] memory _picks,
        IPrizeDistributionSource.PrizeDistribution memory _prizeDistribution
    ) internal pure returns (uint256 prize, uint256[] memory prizeCounts) {

        // create bitmasks for the PrizeDistribution
        uint256[] memory masks = _createBitMasks(_prizeDistribution);
        uint32 picksLength = uint32(_picks.length);
        uint256[] memory _prizeCounts = new uint256[](_prizeDistribution.tiers.length);

        uint8 maxWinningTierIndex = 0;

        require(
            picksLength <= _prizeDistribution.maxPicksPerUser,
            "DrawCalc/exceeds-max-user-picks"
        );

        // for each pick, find number of matching numbers and calculate prize distributions index
        for (uint32 index = 0; index < picksLength; index++) {
            require(_picks[index] < _totalUserPicks, "DrawCalc/insufficient-user-picks");

            if (index > 0) {
                require(_picks[index] > _picks[index - 1], "DrawCalc/picks-ascending");
            }

            // hash the user random number with the pick value
            uint256 randomNumberThisPick = uint256(
                keccak256(abi.encode(_userRandomNumber, _picks[index]))
            );

            uint8 tiersIndex = _calculateTierIndex(
                randomNumberThisPick,
                _winningRandomNumber,
                masks
            );

            // there is prize for this tier index
            if (tiersIndex < TIERS_LENGTH) {
                if (tiersIndex > maxWinningTierIndex) {
                    maxWinningTierIndex = tiersIndex;
                }
                _prizeCounts[tiersIndex]++;
            }
        }

        // now calculate prizeFraction given prizeCounts
        uint256 prizeFraction = 0;
        uint256[] memory prizeTiersFractions = _calculatePrizeTierFractions(
            _prizeDistribution,
            maxWinningTierIndex
        );

        // multiple the fractions by the prizeCounts and add them up
        for (
            uint256 prizeCountIndex = 0;
            prizeCountIndex <= maxWinningTierIndex;
            prizeCountIndex++
        ) {
            if (_prizeCounts[prizeCountIndex] > 0) {
                prizeFraction +=
                    prizeTiersFractions[prizeCountIndex] *
                    _prizeCounts[prizeCountIndex];
            }
        }

        // return the absolute amount of prize awardable
        // div by 1e9 as prize tiers are base 1e9
        prize = (prizeFraction * _prizeDistribution.prize) / 1e9;
        prizeCounts = _prizeCounts;
    }

    ///@notice Calculates the tier index given the random numbers and masks
    ///@param _randomNumberThisPick users random number for this Pick
    ///@param _winningRandomNumber The winning number for this draw
    ///@param _masks The pre-calculate bitmasks for the prizeDistributions
    ///@return The position within the prize tier array (0 = top prize, 1 = runner-up prize, etc)
    function _calculateTierIndex(
        uint256 _randomNumberThisPick,
        uint256 _winningRandomNumber,
        uint256[] memory _masks
    ) internal pure returns (uint8) {
        uint8 numberOfMatches = 0;
        uint8 masksLength = uint8(_masks.length);

        // main number matching loop
        for (uint8 matchIndex = 0; matchIndex < masksLength; matchIndex++) {
            uint256 mask = _masks[matchIndex];

            if ((_randomNumberThisPick & mask) != (_winningRandomNumber & mask)) {
                // there are no more sequential matches since this comparison is not a match
                if (masksLength == numberOfMatches) {
                    return 0;
                } else {
                    return masksLength - numberOfMatches;
                }
            }

            // else there was a match
            numberOfMatches++;
        }

        return masksLength - numberOfMatches;
    }

    /**
     * @notice Create an array of bitmasks equal to the PrizeDistribution.matchCardinality length
     * @param _prizeDistribution The PrizeDistribution to use to calculate the masks
     * @return An array of bitmasks
     */
    function _createBitMasks(IPrizeDistributionSource.PrizeDistribution memory _prizeDistribution)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory masks = new uint256[](_prizeDistribution.matchCardinality);
        masks[0] =  (2**_prizeDistribution.bitRangeSize) - 1;

        for (uint8 maskIndex = 1; maskIndex < _prizeDistribution.matchCardinality; maskIndex++) {
            // shift mask bits to correct position and insert in result mask array
            masks[maskIndex] = masks[maskIndex - 1] << _prizeDistribution.bitRangeSize;
        }

        return masks;
    }

    /**
     * @notice Calculates the expected prize fraction per PrizeDistributions and distributionIndex
     * @param _prizeDistribution prizeDistribution struct for Draw
     * @param _prizeTierIndex Index of the prize tiers array to calculate
     * @return returns the fraction of the total prize (fixed point 9 number)
     */
    function _calculatePrizeTierFraction(
        IPrizeDistributionSource.PrizeDistribution memory _prizeDistribution,
        uint256 _prizeTierIndex
    ) internal pure returns (uint256) {
         // get the prize fraction at that index
        uint256 prizeFraction = _prizeDistribution.tiers[_prizeTierIndex];

        // calculate number of prizes for that index
        uint256 numberOfPrizesForIndex = _numberOfPrizesForIndex(
            _prizeDistribution.bitRangeSize,
            _prizeTierIndex
        );

        return prizeFraction / numberOfPrizesForIndex;
    }

    /**
     * @notice Generates an array of prize tiers fractions
     * @param _prizeDistribution prizeDistribution struct for Draw
     * @param maxWinningTierIndex Max length of the prize tiers array
     * @return returns an array of prize tiers fractions
     */
    function _calculatePrizeTierFractions(
        IPrizeDistributionSource.PrizeDistribution memory _prizeDistribution,
        uint8 maxWinningTierIndex
    ) internal pure returns (uint256[] memory) {
        uint256[] memory prizeDistributionFractions = new uint256[](
            maxWinningTierIndex + 1
        );

        for (uint8 i = 0; i <= maxWinningTierIndex; i++) {
            prizeDistributionFractions[i] = _calculatePrizeTierFraction(
                _prizeDistribution,
                i
            );
        }

        return prizeDistributionFractions;
    }

    /**
     * @notice Calculates the number of prizes for a given prizeDistributionIndex
     * @param _bitRangeSize Bit range size for Draw
     * @param _prizeTierIndex Index of the prize tier array to calculate
     * @return returns the fraction of the total prize (base 1e18)
     */
    function _numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeTierIndex)
        internal
        pure
        returns (uint256)
    {
        if (_prizeTierIndex > 0) {
            return ( 1 << _bitRangeSize * _prizeTierIndex ) - ( 1 << _bitRangeSize * (_prizeTierIndex - 1) );
        } else {
            return 1;
        }
    }
}
