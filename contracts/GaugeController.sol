// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGaugeController.sol";
import "./libraries/TwabLib.sol";
import "./libraries/ExtendedSafeCastLib.sol";

contract GaugeController is IGaugeController {
    using ExtendedSafeCastLib for uint256;

    /* ================================================================================ */
    /* Initialization                                                                   */
    /* ================================================================================ */

    struct GaugeInfo {
        uint256 weight;
    }

    /// @notice ERC20 token contract address (used to weight gauges)
    IERC20 public token;

    /// @notice TokenVault for stakers rewards/incentives
    address public rewardVault;

    /**
      * @notice Tracks user balance. Balance is used to update target gauge weight balances.
      * @dev    The balance is updated in deposit, withthdraw, gaugeIncrease and gaugeDecrease.
    -----------------------------
    | Address     | Balance     |
    | ----------- | ----------- |
    | 0x111...111 | 0x1000      |
    | 0x222...222 | 0x100000    |
    -----------------------------
    */
    mapping(address => uint256) public balances;
    
    /**
      * @notice Tracks User => Gauge => balance.
      * @dev    The balance is updated in gaugeIncrease and gaugeDecrease.
    ----------------------------------------------
    | User        	| Gauge       	| Balance 	|
    |-------------	|-------------	|---------	|
    | 0x111...111 	| 0x999...999 	| 0x10000  	|
    | 0x111...111 	| 0x999...999 	| 0x30000 	|
    | 0x111...111 	| 0x999...999 	| 0x50000  	|
    ----------------------------------------------
    */
    mapping(address => mapping(address => uint256)) public gaugeBalances;
    
    /**
      * @notice Tracks user rewards for staking.
      * @dev    The rewards is updated in
    -----------------------------
    | Address     | Rewards     |
    | ----------- | ----------- |
    | 0x111...111 | 0x100000    |
    | 0x222...222 | 0x500000    |
    -----------------------------
    */
    mapping(address => uint256) public rewards;

    /// @notice User balances staked in existing Gauge.
    mapping(address => TwabLib.Account) internal gaugeTwabs;

    /// @notice Governance scale set for existing Gauge.
    mapping(address => TwabLib.Account) internal gaugeScaleTwabs;

    /**
     * @notice GaugeController Construction
     * @param _token ERC20 contract address (used to weight gauges)
     * @param _tokenVault  TokenVault to store ERC20 balances for stakers
    */
    constructor (
        IERC20 _token,
        address _tokenVault
    ) {
        token = _token;
        rewardVault = _tokenVault;
    }

    modifier requireGauge(address _gauge) {
        require(isGauge(_gauge), "GaugeController:invalid-address");
        _;
    }

    /* ================================================================================ */
    /* External Functions                                                               */
    /* ================================================================================ */

    function isGauge(address _gauge) public view returns (bool) {
        return gaugeScaleTwabs[_gauge].details.balance > 0;
    }

    /**
     * @notice Deposit tokens in GaugeController and increase User balance.
     * @param _to  Receivzer of the deposited tokens
     * @param _amount  Amount of tokens to be deposited
    */
    function deposit(address _to, uint256 _amount) public {
        balances[_to] += _amount;
        token.transferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Withdraw tokens in GaugeController and increase User balance.
     * @param _amount  Amount of tokens to be withdrawn
    */
    function withdraw(uint256 _amount) public {
        balances[msg.sender] -= _amount;
        token.transfer(msg.sender, _amount);
    }

    /**
     * @notice Increase Gauge balance by decreasing User staked balance.
     * @param _gauge  Address of the Gauge
     * @param _amount Amount of tokens to be debited from the User balance and credited to the Gauge balance
    */
    function increaseGauge(address _gauge, uint256 _amount) public requireGauge(_gauge) {
        balances[msg.sender] -= _amount;
        gaugeBalances[msg.sender][_gauge] += _amount;
        TwabLib.Account storage gaugeTwab = gaugeTwabs[_gauge];
        (
            TwabLib.AccountDetails memory twabDetails,,
        ) = TwabLib.increaseBalance(gaugeTwab, _amount.toUint208(), uint32(block.timestamp));
        gaugeTwab.details = twabDetails;
    }

    /**
     * @notice Decrease Gauge balance and increase User staked balance.
     * @param _gauge  Address of the Gauge
     * @param _amount Amount of tokens to be debited from the Gauge balance and credited to the Gauge balance
    */
    function decreaseGauge(address _gauge, uint256 _amount) public requireGauge(_gauge) {
        balances[msg.sender] += _amount;
        gaugeBalances[msg.sender][_gauge] -= _amount;
        TwabLib.Account storage gaugeTwab = gaugeTwabs[_gauge];
        (
            TwabLib.AccountDetails memory twabDetails,,
        ) = TwabLib.decreaseBalance(gaugeTwab, _amount.toUint208(), "insuff", uint32(block.timestamp));
        gaugeTwab.details = twabDetails;
    }

    /// @TODO: Add Governance/Executive authorization modifier/function.
    /**
     * @notice Add new gauge with "1e18" scale to the GaugeController.
     * @param _gauge Address of the Gauge
     */
    function addGauge(address _gauge) public {
        addGaugeWithScale(_gauge, 1 ether);
    }

    /// @TODO: Add Governance/Executive authorization modifier/function.
    /**
     * @notice Add new gauge and target scale to the GaugeController.
     * @param _gauge Address of new Gauge
     * @param _scale Amount to scale new Gauge by
    */
    function addGaugeWithScale(address _gauge, uint256 _scale) public {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        (
            TwabLib.AccountDetails memory twabDetails,,
        ) = TwabLib.increaseBalance(gaugeScaleTwab, _scale.toUint208(), uint32(block.timestamp));
        gaugeScaleTwab.details = twabDetails;
    }

    /// @TODO: Add Governance/Executive authorization modifier/function.
    /**
     * @notice Remove gauge from the GaugeController.
     * @param _gauge Address of existing Gauge
    */
    function removeGauge(address _gauge) public {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        TwabLib.AccountDetails memory twabDetails = gaugeScaleTwab.details;
        (
            twabDetails,,
        ) = TwabLib.decreaseBalance(gaugeScaleTwab, twabDetails.balance, "insuff", uint32(block.timestamp));
        gaugeScaleTwab.details = twabDetails;
    }

    /// @TODO: Add Governance/Executive authorization modifier/function.
    /**
     * @notice Set Gauge target scale.
     * @param _gauge Address of existing Gauge
     * @param _scale Amount to scale existing Gauge by
    */
    function setGaugeScale(address _gauge, uint256 _scale) public {
        TwabLib.Account storage gaugeScaleTwab = gaugeScaleTwabs[_gauge];
        TwabLib.AccountDetails memory twabDetails = gaugeScaleTwab.details;
        if (twabDetails.balance > _scale) {
            (
                twabDetails,,
            ) = TwabLib.decreaseBalance(gaugeScaleTwab, twabDetails.balance - _scale.toUint208(), "insuff", uint32(block.timestamp));
        } else {
            (
                twabDetails,,
            ) = TwabLib.increaseBalance(gaugeScaleTwab, _scale.toUint208() - twabDetails.balance, uint32(block.timestamp));
        }
        gaugeScaleTwab.details = twabDetails;
    }

    /**
     * @notice Read Gauge balance.
     * @param _gauge Address of existing Gauge
     * @return uint256 GaugeTWAB.details.balance
    */
    function getGauge(address _gauge) public view returns (uint256) {
        return gaugeTwabs[_gauge].details.balance;
    }

    /**
     * @notice Read Gauge scaled balance.
     * @param _gauge Address of existing Gauge
     * @return uint256 GaugeScaleTWAB.details.balance
    */
    function getGaugeScale(address _gauge) public view returns (uint256) {
        return gaugeScaleTwabs[_gauge].details.balance;
    }

    /**
     * @notice Calculate Gauge weighted balance using Staked AND Scaled time-weighted average balances.
     * @param _gauge Address of existing Gauge
     * @param _startTime Unix timestamp to signal START of the Binary search
     * @param _endTime Unix timestamp to signal END of the Binary search
     * @return uint256 Weighted(Staked * Scaled) Gauge Balance
    */
    function getScaledAverageGaugeBetween(address _gauge, uint256 _startTime, uint256 _endTime) external override view returns (uint256) {
        uint256 gauge = _getAverageGaugeBetween(_gauge, _startTime, _endTime);
        uint256 gaugeScale = _getAverageGaugeScaleBetween(_gauge, _startTime, _endTime);
        return (gauge*gaugeScale) / 1 ether;
    }

    /**
     * @notice Calculate Gauge average balance between two timestamps.
     * @param _gauge Address of existing Gauge
     * @param _startTime Unix timestamp to signal START of the Binary search
     * @param _endTime Unix timestamp to signal END of the Binary search
     * @return uint256 Gauge average staked balance between two timestamps.
    */
    function getAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime) external view returns (uint256) {
        return _getAverageGaugeBetween(_gauge, _startTime, _endTime);
    }

     /**
     * @notice Calculate Gauge average scale between two timestamps.
     * @param _gauge Address of existing Gauge
     * @param _startTime Unix timestamp to signal START of the Binary search
     * @param _endTime Unix timestamp to signal END of the Binary search
     * @return uint256 Gauge average scaled balance between two timestamps.
    */
    function getAverageGaugeScaleBetween(address _gauge, uint256 _startTime, uint256 _endTime) external view returns (uint256) {
        return _getAverageGaugeScaleBetween(_gauge, _startTime, _endTime);
    }

    /* ================================================================================ */
    /* Internal Functions                                                               */
    /* ================================================================================ */

    function _getAverageGaugeBalanceBetween(address _gauge, uint256 _startTime, uint256 _endTime) internal view returns (uint256) {
        TwabLib.AccountDetails memory gaugeDetails = gaugeTwabs[_gauge].details;
        return TwabLib.getAverageBalanceBetween(
            gaugeTwabs[_gauge].twabs,
            gaugeDetails,
            uint32(_startTime),
            uint32(_endTime),
            uint32(block.timestamp)
        );
    }

    function _getAverageGaugeScaleBetween(address _gauge, uint256 _startTime, uint256 _endTime) internal view returns (uint256) {
        TwabLib.AccountDetails memory gaugeScaleDetails = gaugeScaleTwabs[_gauge].details;
        return TwabLib.getAverageBalanceBetween(
            gaugeScaleTwabs[_gauge].twabs,
            gaugeScaleDetails,
            uint32(_startTime),
            uint32(_endTime),
            uint32(block.timestamp)
        );
    }
}
