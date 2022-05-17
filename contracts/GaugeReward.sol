// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@pooltogether/owner-manager-contracts/contracts/Ownable.sol";

import "./interfaces/IGaugeReward.sol";
import "./GaugeController.sol";

contract GaugeReward is IGaugeReward, Ownable {
    /* ============ Variables ============ */

    /**
     * @notice Tracks rewards tokens per user
     * @dev user => token => rewards
     */
    mapping(address => mapping(address => uint256)) public userTokenRewards;

    /**
     * @notice Tracks user token gauge exchange rate
     * @dev user => token => gauge => exchange rate
     */
    mapping(address => mapping(address => mapping(address => uint256)))
        public userTokenGaugeExchangeRates;

    /**
     * @notice Tracks user last claimed timestamp
     * @dev user => timestamp
     */
    mapping(address => uint256) public userLastClaimedTimestamp;

    /**
     * @notice Tracks token gauge exchange rates
     * @dev token => gauge => exchange rate
     */
    mapping(address => mapping(address => uint256)) public tokenGaugeExchangeRates;

    /**
     * @notice Tracks reward tokens per gauge
     * @dev gauge => reward tokens array
     */
    mapping(address => RewardToken[]) public gaugeRewardTokens;

    /// @notice GaugeController contract address
    GaugeController public gaugeController;

    /**
     * @notice RewardToken struct
     * @param token Address of the reward token
     * @param timestamp Timestamp at which the reward token was added
     */
    struct RewardToken {
        address token;
        uint64 timestamp;
    }

    /* ============ Events ============ */

    /**
     * @notice Emitted when the contract is initialized
     * @param gaugeController Address of the GaugeController
     */
    event Deployed(IGaugeController indexed gaugeController);

    /**
     * @notice Emitted when a user claimed their rewards for a given gauge and token
     * @param gauge Address of the gauge for which the user claimed rewards
     * @param token Address of the token for which the user claimed rewards
     * @param user Address of the user who claimed rewards
     * @param oldStakeBalance Old stake balance of the user
     */
    event Claimed(address gauge, address token, address user, uint256 oldStakeBalance);

    /* ============ Constructor ============ */

    /**
     * @notice GaugeReward constructor
     * @param _gaugeController Address of the GaugeController
     * @param _owner Address of the contract owner
     */
    constructor(GaugeController _gaugeController, address _owner) Ownable(_owner) {
        require(_owner != address(0), "GReward/owner-not-zero-address");
        require(address(_gaugeController) != address(0), "GReward/GC-not-zero-address");
        gaugeController = _gaugeController;

        emit Deployed(_gaugeController);
    }

    /* ============ External Functions ============ */

    /**
     * @notice Return the current reward token for the given gauge.
     * @param _gauge Address of the gauge to get current reward token for
     * @return Current reward token for the given gauge
     */
    function currentRewardToken(address _gauge) external view returns (RewardToken memory) {
        return _currentRewardToken(_gauge);
    }

    /**
     * @notice Add rewards denominated in `token` for the given `gauge`.
     * @dev Only callable by the owner.
     * @dev Will push token to the `gaugeRewardTokens` mapping if different from the current one.
     * @param _gauge Address of the gauge to add rewards for
     * @param _token Address of the token to add rewards for
     * @param _amount Amount of rewards to add
     */
    function addRewards(
        address _gauge,
        address _token,
        uint256 _amount
    ) external onlyOwner {
        if (_token != _currentRewardToken(_gauge).token) {
            _pushRewardToken(_gauge, _token);
        }

        uint256 _currentStakedAmount = gaugeController.getGaugeBalance(_gauge);

        // Delta exchange rate = amount / current staked amount on gauge
        tokenGaugeExchangeRates[_token][_gauge] += (_amount * 1e18) / _currentStakedAmount;
    }

    /// @inheritdoc IGaugeReward
    function afterIncreaseGauge(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) external override {
        RewardToken memory token = _claimCatchup(_gauge, _user, _oldStakeBalance);

        _claim(_gauge, token.token, _user, _oldStakeBalance, false);
        userLastClaimedTimestamp[_user] = block.timestamp;
    }

    /// @inheritdoc IGaugeReward
    function afterDecreaseGauge(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) external override {
        RewardToken memory _rewardToken = _claimCatchup(_gauge, _user, _oldStakeBalance);
        _claim(_gauge, _rewardToken.token, _user, _oldStakeBalance, false);
        userLastClaimedTimestamp[_user] = block.timestamp;
    }

    /**
     * @notice Claim user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _token Address of the token to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @return Amount of rewards claimed
     */
    function claim(
        address _gauge,
        address _token,
        address _user
    ) external returns (uint256) {
        uint256 _oldStakeBalance = gaugeController.gaugeBalances(_gauge, _user);

        _claimCatchup(_gauge, _user, _oldStakeBalance);
        _claim(_gauge, _token, _user, _oldStakeBalance, false);

        userLastClaimedTimestamp[_user] = block.timestamp;

        emit Claimed(_gauge, _token, _user, _oldStakeBalance);

        return _oldStakeBalance;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Return the current reward token for the given gauge
     * @param _gauge Address of the gauge to get current reward token for
     * @return Current reward token for the given gauge
     */
    function _currentRewardToken(address _gauge) internal view returns (RewardToken memory) {
        RewardToken[] memory _gaugeRewardTokens = gaugeRewardTokens[_gauge];

        return _gaugeRewardTokens[_gaugeRewardTokens.length - 1];
    }

    /**
     * @notice Claim user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _token Address of the token to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _oldStakeBalance Old stake balance of the user
     * @param _catchup Whether this function is called in `_claimCatchup` or not
     */
    function _claim(
        address _gauge,
        address _token,
        address _user,
        uint256 _oldStakeBalance,
        bool _catchup
    ) internal {
        uint256 _oldExchangeRate = userTokenGaugeExchangeRates[_user][_token][_gauge];
        uint256 _currentExchangeRate = tokenGaugeExchangeRates[_token][_gauge];

        if (!_catchup && _oldExchangeRate == 0) {
            _oldExchangeRate = _currentExchangeRate;
        }

        // rewards = deltaExchangeRate * oldStakeBalance
        userTokenRewards[_user][_token] +=
            (_currentExchangeRate - _oldExchangeRate) *
            _oldStakeBalance;

        // Record current exchange rate
        userTokenGaugeExchangeRates[_user][_token][_gauge] = _currentExchangeRate;
    }

    /**
     * @notice Claim user rewards for a given gauge.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _oldStakeBalance Old stake balance of the user
     */
    function _claimCatchup(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) internal returns (RewardToken memory) {
        uint256 _userLastClaimedTimestamp = userLastClaimedTimestamp[_user];
        uint256 _gaugeRewardTokenslength = gaugeRewardTokens[_gauge].length;

        RewardToken memory _rewardToken;
        RewardToken memory _latestRewardToken;

        if (_gaugeRewardTokenslength > 1) {
            for (uint256 i = _gaugeRewardTokenslength - 1; i >= 0; i--) {
                _rewardToken = gaugeRewardTokens[_gauge][i];

                if (i == _gaugeRewardTokenslength - 1) {
                    _latestRewardToken = _rewardToken;
                }

                if (_rewardToken.timestamp > _userLastClaimedTimestamp) {
                    _claim(_gauge, _rewardToken.token, _user, _oldStakeBalance, true);
                } else {
                    break;
                }
            }
        }

        return _latestRewardToken;
    }

    /**
     * @notice Push a new reward token into the `gaugeRewardTokens` array
     * @param _gauge Address of the gauge to push reward token for
     * @param _token Address of the reward token to push
     */
    function _pushRewardToken(address _gauge, address _token) internal {
        gaugeRewardTokens[_gauge].push(
            RewardToken({ token: _token, timestamp: uint64(block.timestamp) })
        );
    }
}
