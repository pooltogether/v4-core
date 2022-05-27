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
     * @dev user => reward token address => balance
     */
    mapping(address => mapping(IERC20 => uint256)) public userRewardTokenBalances;

    /**
     * @notice Tracks reward token exchange rate per user and gauge
     * @dev user => gauge => reward token address => reward token timestamp => exchange rate
     */
    mapping(address => mapping(address => mapping(IERC20 => mapping(uint64 => uint256))))
        public userGaugeRewardTokenExchangeRates;

    /**
     * @notice Tracks user last claimed timestamp per gauge and reward token
     * @dev user => gauge => reward token address => timestamp
     */
    mapping(address => mapping(address => mapping(address => uint256)))
        public userGaugeRewardTokenLastClaimedTimestamp;

    /**
     * @notice Tracks reward token exchange rates per gauge
     * @dev gauge => reward token address => reward token timestamp => exchange rate
     */
    mapping(address => mapping(IERC20 => mapping(uint64 => uint256)))
        public gaugeRewardTokenExchangeRates;

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
     * @notice Get user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to get rewards for
     * @param _rewardToken Reward token to get rewards for
     * @param _user Address of the user to get rewards for
     * @return Amount of rewards for the given gauge and token
     */
    function getRewards(
        address _gauge,
        RewardToken memory _rewardToken,
        address _user
    ) external view returns (uint256) {
        uint256 _stakeBalance = gaugeController.getUserGaugeBalance(_gauge, _user);
        (uint256 _rewards, ) = _getRewards(_gauge, _rewardToken, _user, _stakeBalance);

        return _rewards;
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

        RewardToken memory _rewardToken = _currentRewardToken(_gauge);

        if (_token != _rewardToken.token) {
            uint256 _currentTimestamp = block.timestamp;

            gaugeRewardTokens[_gauge].push(
                RewardToken({ token: _token, timestamp: uint64(_currentTimestamp) })
            );

            emit RewardTokenPushed(_gauge, _token, _currentTimestamp);

            _rewardToken = _currentRewardToken(_gauge);
        }

        uint256 _gaugeRewards = (_tokenAmount * stakerCut) / 1e9;

        // Exchange rate = amount / current staked amount on gauge
        uint256 _exchangeRate = (_gaugeRewards * 1e18) / gaugeController.getGaugeBalance(_gauge);

        gaugeRewardTokenExchangeRates[_gauge][_rewardToken.token][
            _rewardToken.timestamp
        ] += _exchangeRate;

        emit RewardsAdded(_gauge, _token, _tokenAmount, _gaugeRewards, _exchangeRate);
    }

    /// @inheritdoc IGaugeReward
    function afterIncreaseGauge(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) external override onlyGaugeController {
        _claimAll(_gauge, _user, _oldStakeBalance);
    }

    /// @inheritdoc IGaugeReward
    function afterDecreaseGauge(
        address _gauge,
        address _user,
        uint256 _oldStakeBalance
    ) external override onlyGaugeController {
        _claimAll(_gauge, _user, _oldStakeBalance);
    }

    /**
     * @notice Claim user rewards for a given gauge and reward token.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _rewardToken Reward token to claim rewards for
     * @param _user Address of the user to claim rewards for
     */
    function claim(
        address _gauge,
        RewardToken memory _rewardToken,
        address _user
    ) external {
        uint256 _stakeBalance = gaugeController.getUserGaugeBalance(_gauge, _user);
        _claim(_gauge, _rewardToken, _user, _stakeBalance);
    }

    /**
     * @notice Claim all user rewards for a given gauge.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _user Address of the user to claim rewards for
     */
    function claimAll(address _gauge, address _user) external {
        uint256 _stakeBalance = gaugeController.getUserGaugeBalance(_gauge, _user);
        _claimAll(_gauge, _user, _stakeBalance);
    }

    /**
     * @notice Redeem user rewards for a given token.
     * @dev Rewards can be redeemed on behalf of a user.
     * @param _user Address of the user to redeem rewards for
     * @param _token Address of the token to redeem rewards for
     * @return Amount of rewards redeemed
     */
    function redeem(address _user, IERC20 _token) external returns (uint256) {
        uint256 _rewards = userRewardTokenBalances[_user][_token];

        userRewardTokenBalances[_user][_token] = 0;
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
     * @notice Get user last claimed timestamp for a given gauge and reward token
     * @param _user Address of the user to set last claimed timestamp for
     * @param _gauge Address of the gauge to set last claimed timestamp for
     * @param _rewardTokenAddress Address of the reward token to set last claimed timestamp for
     * @return Last claimed timestamp for the given gauge and reward token
     */
    function _getUserGaugeRewardTokenLastClaimedTimestamp(
        address _user,
        address _gauge,
        address _rewardTokenAddress
    ) internal view returns (uint256) {
        return userGaugeRewardTokenLastClaimedTimestamp[_user][_gauge][_rewardTokenAddress];
    }

    /**
     * @notice Set user last claimed timestamp for a given gauge and reward token
     * @param _user Address of the user to set last claimed timestamp for
     * @param _gauge Address of the gauge to set last claimed timestamp for
     * @param _rewardTokenAddress Address of the reward token to set last claimed timestamp for
     */
    function _setUserGaugeRewardTokenLastClaimedTimestamp(
        address _user,
        address _gauge,
        address _rewardTokenAddress
    ) internal {
        userGaugeRewardTokenLastClaimedTimestamp[_user][_gauge][_rewardTokenAddress] = uint64(
            block.timestamp
        );
    }

    /**
     * @notice Get user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to get rewards for
     * @param _rewardToken Reward token to get rewards for
     * @param _user Address of the user to get rewards for
     * @param _stakeBalance User stake balance
     * @return _rewards Amount of rewards for the given gauge and token
     * @return _exchangeRate Current exchange rate for the given gauge and token
     */
    function _getRewards(
        address _gauge,
        RewardToken memory _rewardToken,
        address _user,
        uint256 _stakeBalance
    ) internal view returns (uint256 _rewards, uint256 _exchangeRate) {
        uint256 _previousExchangeRate = userGaugeRewardTokenExchangeRates[_user][_gauge][
            _rewardToken.token
        ][_rewardToken.timestamp];

        uint256 _currentExchangeRate = gaugeRewardTokenExchangeRates[_gauge][_rewardToken.token][
            _rewardToken.timestamp
        ];

        uint256 _userLastClaimedTimestamp = _getUserGaugeRewardTokenLastClaimedTimestamp(
            _user,
            _gauge,
            address(_rewardToken.token)
        );

        if (_userLastClaimedTimestamp == 0) {
            RewardToken[] memory _gaugeRewardTokens = gaugeRewardTokens[_gauge];
            uint256 _gaugeRewardTokensLength = _gaugeRewardTokens.length;

            if (_gaugeRewardTokensLength > 1) {
                RewardToken memory _previousRewardToken = _gaugeRewardTokens[
                    _gaugeRewardTokensLength - 1
                ];

                // User may have claimed rewards for the previous reward token
                _userLastClaimedTimestamp = _getUserGaugeRewardTokenLastClaimedTimestamp(
                    _user,
                    _gauge,
                    address(_previousRewardToken.token)
                );
            }

            if (_userLastClaimedTimestamp == 0) {
                // User may have claimed rewards before any tokens were set for the gauge
                _userLastClaimedTimestamp = _getUserGaugeRewardTokenLastClaimedTimestamp(
                    _user,
                    _gauge,
                    address(0)
                );
            }
        }

        bool _isEligibleForPastRewards = _userLastClaimedTimestamp > 0 &&
            _rewardToken.timestamp > _userLastClaimedTimestamp;

        // User is not eligible for any rewards, we return early
        if (!_isEligibleForPastRewards && _previousExchangeRate == 0) {
            return (0, _currentExchangeRate);
        }

        return (
            // Rewards = deltaExchangeRate * stakeBalance
            ((_currentExchangeRate - _previousExchangeRate) * _stakeBalance) / 1e18,
            _currentExchangeRate
        );
    }

    /**
     * @notice Claim user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _rewardToken Reward token to get rewards for
     * @param _user Address of the user to claim rewards for
     * @param _stakeBalance User stake balance
     */
    function _claimRewards(
        address _gauge,
        RewardToken memory _rewardToken,
        address _user,
        uint256 _stakeBalance
    ) internal returns (uint256) {
        (uint256 _rewards, uint256 _exchangeRate) = _getRewards(
            _gauge,
            _rewardToken,
            _user,
            _stakeBalance
        );

        userGaugeRewardTokenExchangeRates[_user][_gauge][_rewardToken.token][
            _rewardToken.timestamp
        ] = _exchangeRate;

        if (_rewards > 0) {
            userRewardTokenBalances[_user][_rewardToken.token] += _rewards;
            emit RewardsClaimed(_gauge, _rewardToken.token, _user, _rewards, _exchangeRate);
        }

        return _rewards;
    }

    /**
     * @notice Claim user rewards for a given gauge and token.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _rewardToken Reward token to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _stakeBalance User stake balance
     */
    function _claim(
        address _gauge,
        RewardToken memory _rewardToken,
        address _user,
        uint256 _stakeBalance
    ) internal {
        _claimRewards(_gauge, _rewardToken, _user, _stakeBalance);
        _setUserGaugeRewardTokenLastClaimedTimestamp(_user, _gauge, address(_rewardToken.token));
    }

    /**
     * @notice Claim all user rewards for a given gauge.
     * @dev Go through all the reward tokens for the given gauge and claim rewards.
     * @param _gauge Address of the gauge to claim rewards for
     * @param _user Address of the user to claim rewards for
     * @param _stakeBalance User stake balance
     */
    function _claimAll(
        address _gauge,
        address _user,
        uint256 _stakeBalance
    ) internal {
        uint256 _gaugeRewardTokensLength = gaugeRewardTokens[_gauge].length;

        RewardToken memory _rewardToken;

        if (_gaugeRewardTokensLength > 0) {
            uint256 i = _gaugeRewardTokensLength;

            while (i > 0) {
                i = i - 1;
                _rewardToken = gaugeRewardTokens[_gauge][i];
                _claimRewards(_gauge, _rewardToken, _user, _stakeBalance);
                _setUserGaugeRewardTokenLastClaimedTimestamp(
                    _user,
                    _gauge,
                    address(_rewardToken.token)
                );
            }
        } else {
            // If no reward token has been added yet, set claimed timestamp for reward token 0
            _setUserGaugeRewardTokenLastClaimedTimestamp(_user, _gauge, address(0));
        }
    }

    /* ============ Modifiers ============ */

    /// @notice Restricts call to GaugeController contract
    modifier onlyGaugeController() {
        require(msg.sender == address(gaugeController), "GReward/only-GaugeController");
        _;
    }
}
