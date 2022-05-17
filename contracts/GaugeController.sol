// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IGaugeController.sol";
import "./interfaces/IGaugeReward.sol";
import "./libraries/TwabLib.sol";
import "./libraries/ExtendedSafeCastLib.sol";

contract GaugeController is IGaugeController {
    using ExtendedSafeCastLib for uint256;

    struct GaugeInfo {
        uint256 weight;
    }

    IERC20 public token;
    IGaugeReward public gaugeReward;

    /**
     * @notice Tracks user deposit balance
     * @dev user => balance
     */
    mapping(address => uint256) public balances;

    /**
     * @notice Tracks user balance per gauge
     * @dev user => gauge => balance
     */
    mapping(address => mapping(address => uint256)) public gaugeBalances;

    /**
     * @notice Tracks user gauge stake balance
     */
    // records total voting power in a gauge
    mapping(address => TwabLib.Account) internal gaugeTwabs;

    // records scales for gauges.
    mapping(address => TwabLib.Account) internal gaugeScaleTwabs;

    constructor(IERC20 _token, IGaugeReward _gaugeReward) {
        token = _token;
        gaugeReward = _gaugeReward;
    }

    function deposit(address _to, uint256 _amount) public {
        balances[_to] += _amount;
        token.transferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 _amount) public {
        balances[msg.sender] -= _amount;
        token.transfer(msg.sender, _amount);
    }

    function increaseGauge(address _gauge, uint256 _amount) public requireGauge(_gauge) {
        balances[msg.sender] -= _amount;
        gaugeBalances[msg.sender][_gauge] += _amount;

        TwabLib.Account storage gaugeTwab = gaugeTwabs[_gauge];
        (TwabLib.AccountDetails memory twabDetails, , ) = TwabLib.increaseBalance(
            gaugeTwab,
            _amount.toUint208(),
            uint32(block.timestamp)
        );

        gaugeTwab.details = twabDetails;

        gaugeReward.afterIncreaseGauge(_gauge, msg.sender, uint256(twabDetails.balance) - _amount);
    }

    function decreaseGauge(address _gauge, uint256 _amount) public requireGauge(_gauge) {
        balances[msg.sender] += _amount;
        gaugeBalances[msg.sender][_gauge] -= _amount;

        TwabLib.Account storage gaugeTwab = gaugeTwabs[_gauge];
        (TwabLib.AccountDetails memory twabDetails, , ) = TwabLib.decreaseBalance(
            gaugeTwab,
            _amount.toUint208(),
            "insuff",
            uint32(block.timestamp)
        );

        gaugeTwab.details = twabDetails;

        gaugeReward.afterDecreaseGauge(_gauge, msg.sender, uint256(twabDetails.balance) + _amount);
    }

    function addGauge(address _gauge) public {
        addGaugeWithScale(_gauge, 1 ether);
    }

    function addGaugeWithScale(address _gauge, uint256 _scale) public {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        (TwabLib.AccountDetails memory twabDetails, , ) = TwabLib.increaseBalance(
            gaugeScaleTwab,
            _scale.toUint208(),
            uint32(block.timestamp)
        );
        gaugeScaleTwab.details = twabDetails;
    }

    function removeGauge(address _gauge) public {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        TwabLib.AccountDetails memory twabDetails = gaugeScaleTwab.details;
        (twabDetails, , ) = TwabLib.decreaseBalance(
            gaugeScaleTwab,
            twabDetails.balance,
            "insuff",
            uint32(block.timestamp)
        );
        gaugeScaleTwab.details = twabDetails;
    }

    function setGaugeScale(address _gauge, uint256 _scale) public {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        TwabLib.AccountDetails memory twabDetails = gaugeScaleTwab.details;
        if (twabDetails.balance > _scale) {
            (twabDetails, , ) = TwabLib.decreaseBalance(
                gaugeScaleTwab,
                twabDetails.balance - _scale.toUint208(),
                "insuff",
                uint32(block.timestamp)
            );
        } else {
            (twabDetails, , ) = TwabLib.increaseBalance(
                gaugeScaleTwab,
                _scale.toUint208() - twabDetails.balance,
                uint32(block.timestamp)
            );
        }
        gaugeScaleTwab.details = twabDetails;
    }

    function getGaugeBalance(address _gauge) public view returns (uint256) {
        return gaugeTwabs[_gauge].details.balance;
    }

    function getGaugeScaleBalance(address _gauge) public view returns (uint256) {
        return gaugeScaleTwabs[_gauge].details.balance;
    }

    function getScaledAverageGaugeBetween(
        address _gauge,
        uint256 _startTime,
        uint256 _endTime
    ) external view override returns (uint256) {
        uint256 gauge = _getAverageGaugeBetween(_gauge, _startTime, _endTime);
        uint256 gaugeScale = _getAverageGaugeScaleBetween(_gauge, _startTime, _endTime);
        return (gauge * gaugeScale) / 1 ether;
    }

    function getAverageGaugeBetween(
        address _gauge,
        uint256 _startTime,
        uint256 _endTime
    ) external view returns (uint256) {
        return _getAverageGaugeBetween(_gauge, _startTime, _endTime);
    }

    function getAverageGaugeScaleBetween(
        address _gauge,
        uint256 _startTime,
        uint256 _endTime
    ) external view returns (uint256) {
        return _getAverageGaugeScaleBetween(_gauge, _startTime, _endTime);
    }

    function _getAverageGaugeBetween(
        address _gauge,
        uint256 _startTime,
        uint256 _endTime
    ) internal view returns (uint256) {
        TwabLib.AccountDetails memory gaugeDetails = gaugeTwabs[_gauge].details;
        return
            TwabLib.getAverageBalanceBetween(
                gaugeTwabs[_gauge].twabs,
                gaugeDetails,
                uint32(_startTime),
                uint32(_endTime),
                uint32(block.timestamp)
            );
    }

    function _getAverageGaugeScaleBetween(
        address _gauge,
        uint256 _startTime,
        uint256 _endTime
    ) internal view returns (uint256) {
        TwabLib.AccountDetails memory gaugeScaleDetails = gaugeScaleTwabs[_gauge].details;
        return
            TwabLib.getAverageBalanceBetween(
                gaugeScaleTwabs[_gauge].twabs,
                gaugeScaleDetails,
                uint32(_startTime),
                uint32(_endTime),
                uint32(block.timestamp)
            );
    }

    function isGauge(address _gauge) public view returns (bool) {
        return gaugeScaleTwabs[_gauge].details.balance > 0;
    }

    modifier requireGauge(address _gauge) {
        require(isGauge(_gauge), "Gauge does not exist");
        _;
    }
}
