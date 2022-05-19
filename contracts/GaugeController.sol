// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@pooltogether/owner-manager-contracts/contracts/Ownable.sol";

import "./interfaces/IGaugeController.sol";
import "./interfaces/IGaugeReward.sol";
import "./libraries/TwabLib.sol";
import "./libraries/ExtendedSafeCastLib.sol";

contract GaugeController is IGaugeController, Ownable {
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
    mapping(address => mapping(address => uint256)) public userGaugeBalance;

    /**
     * @notice Tracks gauge total voting power
     * @dev gauge => voting power
     */
    mapping(address => TwabLib.Account) internal gaugeTwabs;

    /**
     * @notice Tracks gauge scale total voting power
     * @dev gauge => scale voting power
     */
    mapping(address => TwabLib.Account) internal gaugeScaleTwabs;

    /* ============ Events ============ */

    /**
     * @notice Event emitted when the GaugeReward contract address is set
     * @param gaugeReward Address of the newly set GaugeReward contract
     */
    event GaugeRewardSet(IGaugeReward gaugeReward);

    /**
     * @notice Event emitted when the contract is deployed
     * @param token Address of the token being staked in the gauge
     */
    event Deployed(IERC20 token);

    /* ============ Constructor ============ */

    /**
     * @notice GaugeController constructor
     * @param _token Address of the token being staked in the gauge
     * @param _owner Address of the contract owner
     */
    constructor(IERC20 _token, address _owner) Ownable(_owner)  {
        require(_owner != address(0), "GC/owner-not-zero-address");
        require(address(_token) != address(0), "GC/token-not-zero-address");
        token = _token;

        emit Deployed(_token);
    }

    /* ============ External Functions ============ */

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
        userGaugeBalance[msg.sender][_gauge] += _amount;

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
        userGaugeBalance[msg.sender][_gauge] -= _amount;

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
        _addGaugeWithScale(_gauge, 1 ether);
    }

    function addGaugeWithScale(address _gauge, uint256 _scale) public {
        _addGaugeWithScale(_gauge, _scale);
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

    /**
     * @notice Set GaugeReward contract
     * @param _gaugeReward Address of the GaugeReward contract
     */
    function setGaugeReward(IGaugeReward _gaugeReward) external onlyOwner {
        require(address(_gaugeReward) != address(0), "GC/GaugeReward-not-zero-address");
        gaugeReward = _gaugeReward;

        emit GaugeRewardSet(_gaugeReward);
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

    /// @inheritdoc IGaugeController
    function getGaugeBalance(address _gauge) external view override returns (uint256) {
        return gaugeTwabs[_gauge].details.balance;
    }

    /// @inheritdoc IGaugeController
    function getGaugeScaleBalance(address _gauge) external view override returns (uint256) {
        return gaugeScaleTwabs[_gauge].details.balance;
    }

    /// @inheritdoc IGaugeController
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

    /// @inheritdoc IGaugeController
    function getUserGaugeBalance(address _gauge, address _user)
        external
        view
        override
        returns (uint256)
    {
        return userGaugeBalance[_user][_gauge];
    }

    /* ============ Internal Functions ============ */

    function _addGaugeWithScale(address _gauge, uint256 _scale) internal {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        (TwabLib.AccountDetails memory twabDetails, , ) = TwabLib.increaseBalance(
            gaugeScaleTwab,
            _scale.toUint208(),
            uint32(block.timestamp)
        );
        gaugeScaleTwab.details = twabDetails;
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
