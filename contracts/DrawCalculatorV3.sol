// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";

import "./interfaces/IDrawBuffer.sol";
import "./interfaces/IDrawCalculatorV3.sol";
import "./interfaces/IGaugeController.sol";
import "./interfaces/IPrizeConfigHistory.sol";

import "./PrizeDistributor.sol";
import "./PrizeConfigHistory.sol";

/**
  * @title  PoolTogether V4 DrawCalculatorV3
  * @author PoolTogether Inc Team
  * @notice The DrawCalculator calculates a user's prize by matching a winning random number against
            their picks. A users picks are generated deterministically based on their address and balance
            of tickets held. Prize payouts are divided into multiple tiers: grand prize, second place, etc...
            A user with a higher average weighted balance (during each draw period) will be given a large number of
            picks to choose from, and thus a higher chance to match the winning numbers.
*/
contract DrawCalculatorV3 is IDrawCalculatorV3, Manageable {
    /// @dev The uint32[] type is extended with a binarySearch(uint32) function.
    using BinarySearchLib for uint32[];

    /* ============ Variables ============ */

    /// @notice GaugeController address
    IGaugeController public gaugeController;

    /// @notice DrawBuffer address
    IDrawBuffer public immutable drawBuffer;

    /// @notice PrizeConfigHistory address
    IPrizeConfigHistory public immutable prizeConfigHistory;

    /// @notice The tiers array length
    uint8 public constant TIERS_LENGTH = 16;

    /* ============ Events ============ */

    /**
    * @notice Emitted when the contract is initialized
    * @param gaugeController Address of the GaugeController
    * @param drawBuffer Address of the DrawBuffer
    * @param prizeConfigHistory Address of the PrizeConfigHistory
    */
    event Deployed(
        IGaugeController indexed gaugeController,
        IDrawBuffer indexed drawBuffer,
        IPrizeConfigHistory indexed prizeConfigHistory
    );

    /* ============ Constructor ============ */

    /**
     * @notice DrawCalculator constructor
     * @param _gaugeController Address of the GaugeController
     * @param _drawBuffer Address of the DrawBuffer to push draws to
     * @param _prizeConfigHistory Address of the PrizeConfigHistory
     * @param _owner Address of the owner
     */
    constructor(
        IGaugeController _gaugeController,
        IDrawBuffer _drawBuffer,
        IPrizeConfigHistory _prizeConfigHistory,
        address _owner
    ) Ownable(_owner) {
        require(address(_gaugeController) != address(0), "DrawCalc/GC-not-zero-address");
        require(address(_drawBuffer) != address(0), "DrawCalc/DB-not-zero-address");
        require(address(_prizeConfigHistory) != address(0), "DrawCalc/PCH-not-zero-address");
        require(_owner != address(0), "DrawCalc/owner-not-zero-address");

        gaugeController = _gaugeController;
        drawBuffer = _drawBuffer;
        prizeConfigHistory = _prizeConfigHistory;

        emit Deployed(_gaugeController, _drawBuffer, _prizeConfigHistory);
    }

    /* ============ External Functions ============ */

    /// @inheritdoc IDrawCalculatorV3
    function calculate(
        ITicket _ticket,
        address _user,
        uint32[] calldata _drawIds,
        uint64 [][] calldata _drawPickIndices
    ) external view override returns (
        uint256[] memory prizesAwardable,
        bytes memory prizeCounts
    ) {
        require(_drawPickIndices.length == _drawIds.length, "DrawCalc/invalid-pick-indices");

        // User address is hashed once.
        bytes32 _userRandomNumber = keccak256(abi.encodePacked(_user));

        (prizesAwardable, prizeCounts) = _calculatePrizesAwardable(
            _ticket,
            _user,
            _userRandomNumber,
            _drawIds,
            _drawPickIndices
        );
    }

    /// @inheritdoc IDrawCalculatorV3
    function calculateUserPicks(
        ITicket _ticket,
        address _user,
        uint32[] calldata _drawIds
    ) external view override returns (uint64[] memory picks) {
        IDrawBeacon.Draw[] memory _draws = drawBuffer.getDraws(_drawIds);
        uint256 _drawsLength = _draws.length;
        picks = new uint64[](_drawIds.length);

        for (uint32 _drawIndex = 0; _drawIndex < _drawsLength; _drawIndex++) {
            IDrawBeacon.Draw memory _draw = _draws[_drawIndex];
            IPrizeConfigHistory.PrizeConfig memory _prizeConfig = prizeConfigHistory.getPrizeConfig(_draw.drawId);

            _requireDrawUnexpired(_draw, _prizeConfig);

            picks[_drawIndex] = _calculateUserPicks(
                _ticket,
                _user,
                _draw.timestamp - _draw.beaconPeriodSeconds,
                _draw.timestamp - _prizeConfig.endTimestampOffset,
                _prizeConfig.poolStakeCeiling,
                _prizeConfig.bitRangeSize,
                _prizeConfig.matchCardinality
            );
        }

        return picks;
    }

    /// @inheritdoc IDrawCalculatorV3
    function getDrawBuffer() external override view returns (IDrawBuffer) {
        return drawBuffer;
    }

    /// @inheritdoc IDrawCalculatorV3
    function getGaugeController() external override view returns (IGaugeController) {
        return gaugeController;
    }

    /// @inheritdoc IDrawCalculatorV3
    function getPrizeConfigHistory() external override view returns (IPrizeConfigHistory) {
        return prizeConfigHistory;
    }

    /// @inheritdoc IDrawCalculatorV3
    function getTotalPicks(
        ITicket _ticket,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _poolStakeCeiling,
        uint8 _bitRange,
        uint8 _cardinality
    ) external override view returns (uint256) {
        return _getTotalPicks(_ticket, _startTime, _endTime, _poolStakeCeiling, _bitRange, _cardinality);
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Ensure that the draw is not expired.
     * @param _draw Draw
     * @param _prizeConfig PrizeConfig
     */
    function _requireDrawUnexpired(
        IDrawBeacon.Draw memory _draw,
        IPrizeConfigHistory.PrizeConfig memory _prizeConfig
    ) internal view {
        require(uint64(block.timestamp) < _draw.timestamp + _prizeConfig.expiryDuration, "DrawCalc/draw-expired");
    }

    /**
     * @notice Calculates the prizes awardable for each DrawIds passed.
     * @param _ticket Address of the ticket to calculate awardable prizes for
     * @param _user Address of the user for which to calculate awardable prizes for
     * @param _userRandomNumber Random number of the user to consider over draws
     * @param _drawIds Array of DrawIds for which to calculate awardable prizes for
     * @param _drawPickIndices Pick indices for each Draw
     */
    function _calculatePrizesAwardable(
        ITicket _ticket,
        address _user,
        bytes32 _userRandomNumber,
        uint32[] memory _drawIds,
        uint64[][] memory _drawPickIndices
    ) internal view returns (
        uint256[] memory prizesAwardable,
        bytes memory prizeCounts
    ) {
        // READ list of IDrawBeacon.Draw using the drawIds from drawBuffer
        IDrawBeacon.Draw[] memory _draws = drawBuffer.getDraws(_drawIds);
        uint256 _drawsLength = _draws.length;

        uint256[] memory _prizesAwardable = new uint256[](_drawIds.length);
        uint256[][] memory _prizeCounts = new uint256[][](_drawIds.length);

        // Calculate prizes awardable for each Draw passed
        for (uint32 _drawIndex = 0; _drawIndex < _drawsLength; _drawIndex++) {
            IDrawBeacon.Draw memory _draw = _draws[_drawIndex];
            IPrizeConfigHistory.PrizeConfig memory _prizeConfig = prizeConfigHistory.getPrizeConfig(_draw.drawId);

            _requireDrawUnexpired(_draw, _prizeConfig);

            uint64 _totalUserPicks = _calculateUserPicks(
                _ticket,
                _user,
                _draw.timestamp - _draw.beaconPeriodSeconds,
                _draw.timestamp - _prizeConfig.endTimestampOffset,
                _prizeConfig.poolStakeCeiling,
                _prizeConfig.bitRangeSize,
                _prizeConfig.matchCardinality
            );

            (_prizesAwardable[_drawIndex], _prizeCounts[_drawIndex]) = _calculate(
                _draw.winningRandomNumber,
                _totalUserPicks,
                _userRandomNumber,
                _drawPickIndices[_drawIndex],
                _prizeConfig
            );
        }

        prizeCounts = abi.encode(_prizeCounts);
        prizesAwardable = _prizesAwardable;
    }

    /**
     * @notice Calculates the number of picks a user gets for a Draw, considering the normalized user balance and the PrizeConfig.
     * @dev Divided by 1e18 since the normalized user balance is stored as a fixed point 18 number.
     * @param _ticket Address of the ticket to get total picks for
     * @param _startTimestamp Timestamp at which the prize starts
     * @param _endTimestamp Timestamp at which the prize ends
     * @param _poolStakeCeiling Globally configured pool stake ceiling
     * @param _bitRange Number of bits allocated to each division
     * @param _cardinality Number of sub-divisions of a random number
     * @return Number of picks a user gets for a Draw
     */
    function _calculateUserPicks(
        ITicket _ticket,
        address _user,
        uint64 _startTimestamp,
        uint64 _endTimestamp,
        uint256 _poolStakeCeiling,
        uint8 _bitRange,
        uint8 _cardinality
    ) internal view returns (uint64) {
        uint256 _numberOfPicks = _getTotalPicks(_ticket, _startTimestamp, _endTimestamp, _poolStakeCeiling, _bitRange, _cardinality);
        uint256 _normalizedBalance = _getNormalizedBalanceAt(_ticket, _user, _startTimestamp, _endTimestamp);
        return uint64((_normalizedBalance * _numberOfPicks) / 1 ether);
    }

    /**
     * @notice Calculates the normalized balance of a user against the total supply for a draw.
     * @param _ticket Address of the ticket to get normalized balance for
     * @param _user The user to consider
     * @param _startTimestamp Timestamp at which the draw starts
     * @param _endTimestamp Timestamp at which the draw ends
     * @return User normalized balance for the draw
     */
    function _getNormalizedBalanceAt(
        ITicket _ticket,
        address _user,
        uint64 _startTimestamp,
        uint64 _endTimestamp
    ) internal view returns (uint256) {
        uint64[] memory _timestampsWithStartCutoffTimes = new uint64[](1);
        uint64[] memory _timestampsWithEndCutoffTimes = new uint64[](1);

        _timestampsWithStartCutoffTimes[0] = _startTimestamp;
        _timestampsWithEndCutoffTimes[0] = _endTimestamp;

        uint256[] memory _balances = _ticket.getAverageBalancesBetween(
            _user,
            _timestampsWithStartCutoffTimes,
            _timestampsWithEndCutoffTimes
        );

        uint256[] memory _totalSupplies = _ticket.getAverageTotalSuppliesBetween(
            _timestampsWithStartCutoffTimes,
            _timestampsWithEndCutoffTimes
        );

        uint256 _normalizedBalance;

        if (_totalSupplies[0] > 0) {
            _normalizedBalance = (_balances[0] * 1 ether) / _totalSupplies[0];
        }

        return _normalizedBalance;
    }

    /**
    * @notice Returns the total number of picks for a prize pool.
    * @param _ticket Address of the ticket to get total picks for
    * @param _startTime Timestamp at which the prize starts
    * @param _endTime Timestamp at which the prize ends
    * @param _poolStakeCeiling Globally configured pool stake ceiling
    * @param _bitRange Number of bits allocated to each division
    * @param _cardinality Number of sub-divisions of a random number
    * @return Total number of picks for a prize pool
    */
    function _getTotalPicks(
        ITicket _ticket,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _poolStakeCeiling,
        uint8 _bitRange,
        uint8 _cardinality
    ) internal view returns (uint256) {
        uint256 _totalChances = (2**_bitRange)**_cardinality;
        uint256 _gaugeScaledAverage = gaugeController.getScaledAverageGaugeBalanceBetween(address(_ticket), _startTime, _endTime);
        return (_gaugeScaledAverage * _totalChances) / _poolStakeCeiling;
    }

    /**
     * @notice Calculates the prize amount for a PrizeConfig over given picks
     * @param _winningRandomNumber  Draw's winningRandomNumber
     * @param _totalUserPicks       Number of picks the user gets for the Draw
     * @param _userRandomNumber     User randomNumber for that draw
     * @param _picks                User picks for that draw
     * @param _prizeConfig          PrizeConfig for that draw
     * @return prize (if any), prizeCounts (if any)
     */
    function _calculate(
        uint256 _winningRandomNumber,
        uint256 _totalUserPicks,
        bytes32 _userRandomNumber,
        uint64[] memory _picks,
        IPrizeConfigHistory.PrizeConfig memory _prizeConfig
    ) internal pure returns (uint256 prize, uint256[] memory prizeCounts) {
        // Create bitmasks for the PrizeConfig
        uint256[] memory masks = _createBitMasks(_prizeConfig.matchCardinality, _prizeConfig.bitRangeSize);
        uint32 picksLength = uint32(_picks.length);
        uint256[] memory _prizeCounts = new uint256[](_prizeConfig.tiers.length);

        uint8 maxWinningTierIndex = 0;

        require(
            picksLength <= _prizeConfig.maxPicksPerUser,
            "DrawCalc/exceeds-max-user-picks"
        );

        // for each pick, find number of matching numbers and calculate prize configs index
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
        uint256[] memory prizeTiersFractions = new uint256[](
            maxWinningTierIndex + 1
        );

        for (uint8 i = 0; i <= maxWinningTierIndex; i++) {
            prizeTiersFractions[i] = _calculatePrizeTierFraction(
                _prizeConfig.tiers[i],
                _prizeConfig.bitRangeSize,
                i
            );
        }

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
        prize = (prizeFraction * _prizeConfig.prize) / 1e9;
        prizeCounts = _prizeCounts;
    }

    /**
     * @notice Calculates the tier index given the random numbers and masks
     * @param _randomNumberThisPick User random number for this Pick
     * @param _winningRandomNumber The winning number for this draw
     * @param _masks The pre-calculated bitmasks for the PrizeConfig
     * @return The position within the prize tier array (0 = top prize, 1 = runner-up prize, etc)
     */
    function _calculateTierIndex(
        uint256 _randomNumberThisPick,
        uint256 _winningRandomNumber,
        uint256[] memory _masks
    ) internal pure returns (uint8) {
        uint8 _numberOfMatches;
        uint8 _masksLength = uint8(_masks.length);

        // main number matching loop
        for (uint8 matchIndex = 0; matchIndex < _masksLength; matchIndex++) {
            uint256 _mask = _masks[matchIndex];

            if ((_randomNumberThisPick & _mask) != (_winningRandomNumber & _mask)) {
                // there are no more sequential matches since this comparison is not a match
                if (_masksLength == _numberOfMatches) {
                    return 0;
                } else {
                    return _masksLength - _numberOfMatches;
                }
            }

            // else there was a match
            _numberOfMatches++;
        }

        return _masksLength - _numberOfMatches;
    }

    /**
     * @notice Creates an array of bitmasks equal to the PrizeConfig.matchCardinality length
     * @param _matchCardinality Match cardinality for Draw
     * @param _bitRangeSize Bit range size for Draw
     * @return Array of bitmasks
     */
    function _createBitMasks(uint8 _matchCardinality, uint8 _bitRangeSize)
        internal
        pure
        returns (uint256[] memory)
    {
        uint256[] memory _masks = new uint256[](_matchCardinality);
        _masks[0] = (2**_bitRangeSize) - 1;

        for (uint8 _maskIndex = 1; _maskIndex < _matchCardinality; _maskIndex++) {
            // shift mask bits to correct position and insert in result mask array
            _masks[_maskIndex] = _masks[_maskIndex - 1] << _bitRangeSize;
        }

        return _masks;
    }

    /**
     * @notice Calculates the expected prize fraction per PrizeConfig and prize tiers index
     * @param _prizeFraction Prize fraction for this PrizeConfig
     * @param _bitRangeSize Bit range size for Draw
     * @param _prizeConfigIndex Index of the prize tiers array to calculate
     * @return returns the fraction of the total prize (fixed point 9 number)
     */
    function _calculatePrizeTierFraction(
        uint256 _prizeFraction,
        uint8 _bitRangeSize,
        uint256 _prizeConfigIndex
    ) internal pure returns (uint256) {
        // calculate number of prizes for that index
        uint256 numberOfPrizesForIndex = _numberOfPrizesForIndex(
            _bitRangeSize,
            _prizeConfigIndex
        );

        return _prizeFraction / numberOfPrizesForIndex;
    }

    /**
     * @notice Calculates the number of prizes for a given PrizeConfigIndex
     * @param _bitRangeSize Bit range size for Draw
     * @param _prizeConfigIndex Index of the PrizeConfig array to calculate
     * @return returns the fraction of the total prize (base 1e18)
     */
    function _numberOfPrizesForIndex(uint8 _bitRangeSize, uint256 _prizeConfigIndex)
        internal
        pure
        returns (uint256)
    {
        if (_prizeConfigIndex > 0) {
            return ( 1 << _bitRangeSize * _prizeConfigIndex ) - ( 1 << _bitRangeSize * (_prizeConfigIndex - 1) );
        } else {
            return 1;
        }
    }
}
