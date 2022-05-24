// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Multicall.sol";

import "./interfaces/IGaugeReward.sol";
import "./interfaces/IGaugeController.sol";
import "./interfaces/IPrizePoolLiquidatorListener.sol";

/**
  * @title  PoolTogether V4 GaugeReward
  * @author PoolTogether Inc Team
  * @notice The GaugeReward contract handles rewards for users
            who staked in one or several gauges on the GaugeController contract.
  * @dev    This contract is only keeping track of the rewards.
            Reward tokens are actually stored in the TokenVault contract.
*/
contract GaugeReward is IGaugeReward, IPrizePoolLiquidatorListener, Multicall {
    using SafeERC20 for IERC20;

    /* ============ Variables ============ */

    /**
     * @notice Tracks user token reward balances
     * @dev user => token => balance
     */
    mapping(address => mapping(IERC20 => uint256)) public userTokenRewardBalances;

    /**
     * @notice Tracks user token gauge exchange rate
     * @dev user => token => gauge => exchange rate
     */
    mapping(address => mapping(IERC20 => mapping(address => uint256)))
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
    mapping(IERC20 => mapping(address => uint256)) public tokenGaugeExchangeRates;

    /**
     * @notice RewardToken struct
     * @param token Address of the reward token
     * @param timestamp Timestamp at which the reward token was added
     */
    struct RewardToken {
        IERC20 token;
        uint64 timestamp;
    }

    /**
     * @notice Tracks reward tokens per gauge
     * @dev gauge => reward tokens array
     */
    mapping(address => RewardToken[]) public gaugeRewardTokens;

    /// @notice GaugeController contract address
    IGaugeController public gaugeController;

    /// @notice Vault contract address
    address public vault;

    /// @notice Address of the liquidator that this contract is listening to
    address public liquidator;

    /// @notice Percentage of rewards that goes to stakers. Fixed point 9 number that is less than 1.
    uint32 public stakerCut;

    /* ============ Events ============ */

    /**
     * @notice Emitted when the contract is deployed
     * @param gaugeController Address of the GaugeController
     * @param vault Address of the Vault
     * @param liquidator Address of the Liquidator
     * @param stakerCut Percentage of rewards that goes to stakers
     */
    event Deployed(
        IGaugeController indexed gaugeController,
        address indexed vault,
        address indexed liquidator,
        uint32 stakerCut
    );

    /**
     * @notice Emitted when tickets are swapped for tokens
     * @param gauge Address of the gauge for which tokens were added
     * @param token Address of the token sent to the vault
     * @param amount Amount of tokens sent to the vault
     * @param stakerRewards Amount of rewards allocated to stakers
     * @param exchangeRate New exchange rate for this `token` in this `gauge`
     */
    event RewardsAdded(
        address indexed gauge,
        IERC20 indexed token,
        uint256 amount,
        uint256 stakerRewards,
        uint256 exchangeRate
    );

    /**
     * @notice Emitted when a user claimed their rewards for a given gauge and token
     * @param gauge Address of the gauge for which the user claimed rewards
     * @param token Address of the token for which the user claimed rewards
     * @param user Address of the user for which the rewards were claimed
     * @param amount Total amount of rewards claimed
     * @param exchangeRate Exchange rate at which the rewards were claimed
     */
    event RewardsClaimed(
        address indexed gauge,
        IERC20 indexed token,
        address indexed user,
        uint256 amount,
        uint256 exchangeRate
    );

    /**
     * @notice Emitted when a user redeemed their rewards for a given token
     * @param caller Address who called the redeem function
     * @param user Address of the user for which the rewards were redeemed
     * @param token Address of the token for which the user redeemed rewards
     * @param amount Total amount of rewards redeemed
     */
    event RewardsRedeemed(
        address indexed caller,
        address indexed user,
        IERC20 indexed token,
        uint256 amount
    );

    /**
     * @notice Emitted when a new reward token is pushed onto the `gaugeRewardTokens` mapping
     * @param gauge Address of the gauge for which the reward token is added
     * @param token Address of the token being pushed
     * @param timestamp Timestamp at which the reward token was pushed
     */
    event RewardTokenPushed(address indexed gauge, IERC20 indexed token, uint256 timestamp);

    /* ============ Constructor ============ */

    /**
     * @notice GaugeReward constructor
     * @param _gaugeController Address of the GaugeController
     * @param _vault Address of the Vault
     * @param _liquidator Address of the Liquidator
     * @param _stakerCut Percentage of rewards that goes to stakers
     */
    constructor(
        IGaugeController _gaugeController,
        address _vault,
        address _liquidator,
        uint32 _stakerCut
    ) {
        require(address(_gaugeController) != address(0), "GReward/GC-not-zero-address");
        require(_vault != address(0), "GReward/Vault-not-zero-address");
        require(_liquidator != address(0), "GReward/Liq-not-zero-address");
        require(_stakerCut < 1e9, "GReward/staker-cut-lt-1e9");

        gaugeController = _gaugeController;
        vault = _vault;
        stakerCut = _stakerCut;
        liquidator = _liquidator;

        emit Deployed(_gaugeController, _vault, _liquidator, _stakerCut);
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
     * @notice Records exchange rate after swapping an amount of `ticket` for `token`.
     * @dev Called by the liquidator contract anytime tokens are liquidated.
     * @dev Will push `token` to the `gaugeRewardTokens` mapping if different from the current one.
     * @param _ticket Address of the tickets that were sold
     * @param _token Address of the token that the tickets were sold for
     * @param _tokenAmount Amount of tokens that the tickets were sold for
     */
    function afterSwap(
        IPrizePool,
        ITicket _ticket,
        uint256,
        IERC20 _token,
        uint256 _tokenAmount
    ) external override {
        require(msg.sender == liquidator, "GReward/only-liquidator");

        address _gauge = address(_ticket);

        if (_token != _currentRewardToken(_gauge).token) {
            _pushRewardToken(_gauge, _token);
        }

        uint256 _gaugeRewards = (_tokenAmount * stakerCut) / 1e9;

        // Exchange rate = amount / current staked amount on gauge
        uint256 _exchangeRate = (_gaugeRewards * 1e18) / gaugeController.getGaugeBalance(_gauge);

        tokenGaugeExchangeRates[_token][_gauge] += _exchangeRate;

        emit RewardsAdded(_gauge, _token, _tokenAmount, _gaugeRewards, _exchangeRate);
    }

    /// @inheritdoc IGaugeReward
    function afterIncreaseGauge(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) external override onlyGaugeController {
        _claim(_gauge, _user, _oldStakeBalance);
    }

    /// @inheritdoc IGaugeReward
    function afterDecreaseGauge(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) external override onlyGaugeController {
        _claim(_gauge, _user, _oldStakeBalance);
    }

    /**
     * @notice Claim user rewards for a given gauge.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _user Address of the user to claim rewards for
     */
    function claim(
        address _gauge,
        address _user
    ) external {
        uint256 _stakeBalance = gaugeController.getUserGaugeBalance(_gauge, _user);
        _claim(_gauge, _user, _stakeBalance);
    }

    /**
     * @notice Redeem user rewards for a given token.
     * @dev Rewards can be redeemed on behalf of a user.
     * @param _user Address of the user to redeem rewards for
     * @param _token Address of the token to redeem rewards for
     * @return Amount of rewards redeemed
     */
    function redeem(address _user, IERC20 _token) external returns (uint256) {
        uint256 _rewards = userTokenRewardBalances[_user][_token];

        userTokenRewardBalances[_user][_token] = 0;
        _token.safeTransferFrom(vault, _user, _rewards);

        emit RewardsRedeemed(msg.sender, _user, _token, _rewards);

        return _rewards;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Return the current reward token for the given gauge
     * @param _gauge Address of the gauge to get current reward token for
     * @return Current reward token for the given gauge
     */
    function _currentRewardToken(address _gauge) internal view returns (RewardToken memory) {
        RewardToken[] memory _gaugeRewardTokens = gaugeRewardTokens[_gauge];
        uint256 _gaugeRewardTokensLength = _gaugeRewardTokens.length;

        if (_gaugeRewardTokensLength > 0) {
            return _gaugeRewardTokens[_gaugeRewardTokensLength - 1];
        } else {
            return RewardToken(IERC20(address(0)), 0);
        }
    }

    /**
     * @notice Claim user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _token Address of the token to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _stakeBalance User stake balance
     * @param _eligibleForPastRewards Whether user is eligible for past rewards or not
     */
    function _claimRewards(
        address _gauge,
        IERC20 _token,
        address _user,
        uint256 _stakeBalance,
        bool _eligibleForPastRewards
    ) internal returns (uint256) {
        uint256 _previousExchangeRate = userTokenGaugeExchangeRates[_user][_token][_gauge];
        uint256 _currentExchangeRate = tokenGaugeExchangeRates[_token][_gauge];

        if (!_eligibleForPastRewards && _previousExchangeRate == 0) {
            _previousExchangeRate = _currentExchangeRate;
        }

        // Rewards = deltaExchangeRate * stakeBalance
        uint256 _rewards = ((_currentExchangeRate - _previousExchangeRate) * _stakeBalance) / 1e18;

        // Record current exchange rate
        userTokenGaugeExchangeRates[_user][_token][_gauge] = _currentExchangeRate;

        // Skip event and rewards accrual if rewards are equal to zero
        if (_rewards > 0) {
            userTokenRewardBalances[_user][_token] += _rewards;

            emit RewardsClaimed(_gauge, _token, _user, _rewards, _currentExchangeRate);
        }

        return _rewards;
    }

    /**
     * @notice Claim user past rewards for a given gauge.
     * @dev Go through all the past reward tokens for the given gauge and claim rewards.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _stakeBalance User stake balance
     */
    function _claimPastRewards(
        address _gauge,
        address _user,
        uint256 _stakeBalance
    ) internal returns (RewardToken memory) {
        uint256 _userLastClaimedTimestamp = userLastClaimedTimestamp[_user];
        uint256 _gaugeRewardTokensLength = gaugeRewardTokens[_gauge].length;

        RewardToken memory _rewardToken;
        RewardToken memory _latestRewardToken;

        if (_gaugeRewardTokensLength > 0) {
            uint256 i = _gaugeRewardTokensLength;

            while (i > 0) {
                i = i - 1;
                _rewardToken = gaugeRewardTokens[_gauge][i];

                if (i == _gaugeRewardTokensLength - 1) {
                    _latestRewardToken = _rewardToken;
                }

                if (
                    _userLastClaimedTimestamp > 0 &&
                    _rewardToken.timestamp > _userLastClaimedTimestamp
                ) {
                    _claimRewards(_gauge, _rewardToken.token, _user, _stakeBalance, true);
                } else {
                    break;
                }
            }
        }

        return _latestRewardToken;
    }

    /**
     * @notice Claim user rewards for a given gauge.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _stakeBalance User stake balance
     */
    function _claim(
        address _gauge,
        address _user,
        uint256 _stakeBalance
    ) internal {
        RewardToken memory _rewardToken = _claimPastRewards(_gauge, _user, _stakeBalance);

        if (address(_rewardToken.token) != address(0)) {
            _claimRewards(_gauge, _rewardToken.token, _user, _stakeBalance, false);
        }

        userLastClaimedTimestamp[_user] = block.timestamp;
    }

    /**
     * @notice Push a new reward token into the `gaugeRewardTokens` array
     * @param _gauge Address of the gauge to push reward token for
     * @param _token Address of the reward token to push
     */
    function _pushRewardToken(address _gauge, IERC20 _token) internal {
        uint256 _currentTimestamp = block.timestamp;

        gaugeRewardTokens[_gauge].push(
            RewardToken({ token: _token, timestamp: uint64(_currentTimestamp) })
        );

        emit RewardTokenPushed(_gauge, _token, _currentTimestamp);
    }

    /* ============ Modifiers ============ */

    /// @notice Restricts call to GaugeController contract
    modifier onlyGaugeController() {
        require(msg.sender == address(gaugeController), "GReward/only-GaugeController");
        _;
    }
}
