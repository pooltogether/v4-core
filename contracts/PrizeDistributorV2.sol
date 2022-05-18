// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "./interfaces/IDrawCalculatorV3.sol";

/**
    * @title  PoolTogether V4 PrizeDistributorV2
    * @author PoolTogether Inc Team
    * @notice The PrizeDistributorV2 contract holds Tickets (captured interest) and distributes tickets to users with winning draw claims.
              PrizeDistributorV2 uses an external IDrawCalculatorV3 to validate a users draw claim, before awarding payouts. To prevent users 
              from reclaiming prizes, a payout history for each draw claim is mapped to user accounts. Reclaiming a draw can occur
              if an "optimal" prize was not included in previous claim pick indices and the new claims updated payout is greater then
              the previous prize distributor claim payout.
*/
contract PrizeDistributorV2 is Manageable {
    using SafeERC20 for IERC20;

    /**
     * @notice Emit when user has claimed token from the PrizeDistributorV2.
     * @param user   User address receiving draw claim payouts
     * @param drawId Draw id that was paid out
     * @param payout Payout for draw
     */
    event ClaimedDraw(address indexed user, uint32 indexed drawId, uint256 payout);

    /**
     * @notice Emit when IDrawCalculatorV3 is set.
     * @param calculator IDrawCalculatorV3 address
     */
    event DrawCalculatorSet(IDrawCalculatorV3 indexed calculator);

    /**
     * @notice Emit when Token is set.
     * @param token Token address
     */
    event TokenSet(IERC20 indexed token);

    /**
     * @notice Emit when ERC20 tokens are withdrawn.
     * @param token  ERC20 token transferred.
     * @param to     Address that received funds.
     * @param amount Amount of tokens transferred.
     */
    event ERC20Withdrawn(IERC20 indexed token, address indexed to, uint256 amount);

    /* ============ Global Variables ============ */

    /// @notice IDrawCalculatorV3 address
    IDrawCalculatorV3 internal drawCalculator;

    /// @notice Token address
    IERC20 internal immutable token;

    /// @notice Maps users => drawId => paid out balance
    mapping(address => mapping(uint256 => uint256)) internal userDrawPayouts;

    /// @notice The vault that stores the prize tokens
    address public vault;

    /* ============ Initialize ============ */

    /**
     * @notice Initialize PrizeDistributorV2 smart contract.
     * @param _owner          Owner address
     * @param _token          Token address
     * @param _drawCalculator IDrawCalculatorV3 address
     */
    constructor(
        address _owner,
        IERC20 _token,
        IDrawCalculatorV3 _drawCalculator,
        address _vault
    ) Ownable(_owner) {
        _setDrawCalculator(_drawCalculator);
        require(address(_token) != address(0), "PrizeDistributorV2/token-not-zero-address");
        token = _token;
        vault = _vault;
        emit TokenSet(_token);
    }

    /* ============ External Functions ============ */

    function claim(
        ITicket _ticket,
        address _user,
        uint32[] calldata _drawIds,
        bytes calldata _data
    ) external returns (uint256) {
        
        uint256 totalPayout;
        
        (uint256[] memory drawPayouts, ) = drawCalculator.calculate(_ticket, _user, _drawIds, _data); // neglect the prizeCounts since we are not interested in them here

        uint256 drawPayoutsLength = drawPayouts.length;
        for (uint256 payoutIndex = 0; payoutIndex < drawPayoutsLength; payoutIndex++) {
            uint32 drawId = _drawIds[payoutIndex];
            uint256 payout = drawPayouts[payoutIndex];
            uint256 oldPayout = _getDrawPayoutBalanceOf(_user, drawId);
            uint256 payoutDiff = 0;

            // helpfully short-circuit, in case the user screwed something up.
            require(payout > oldPayout, "PrizeDistributorV2/zero-payout");

            unchecked {
                payoutDiff = payout - oldPayout;
            }

            _setDrawPayoutBalanceOf(_user, drawId, payout);

            totalPayout += payoutDiff;

            emit ClaimedDraw(_user, drawId, payoutDiff);
        }

        _awardPayout(_user, totalPayout);

        return totalPayout;
    }

    function withdrawERC20(
        IERC20 _erc20Token,
        address _to,
        uint256 _amount
    ) external onlyManagerOrOwner returns (bool) {
        require(_to != address(0), "PrizeDistributorV2/recipient-not-zero-address");
        require(address(_erc20Token) != address(0), "PrizeDistributorV2/ERC20-not-zero-address");

        _erc20Token.safeTransfer(_to, _amount);

        emit ERC20Withdrawn(_erc20Token, _to, _amount);

        return true;
    }

    function getDrawCalculator() external view returns (IDrawCalculatorV3) {
        return drawCalculator;
    }

    function getDrawPayoutBalanceOf(address _user, uint32 _drawId)
        external
        view
        returns (uint256)
    {
        return _getDrawPayoutBalanceOf(_user, _drawId);
    }

    function getToken() external view returns (IERC20) {
        return token;
    }

    function setDrawCalculator(IDrawCalculatorV3 _newCalculator)
        external
        onlyManagerOrOwner
        returns (IDrawCalculatorV3)
    {
        _setDrawCalculator(_newCalculator);
        return _newCalculator;
    }

    /* ============ Internal Functions ============ */

    function _getDrawPayoutBalanceOf(address _user, uint32 _drawId)
        internal
        view
        returns (uint256)
    {
        return userDrawPayouts[_user][_drawId];
    }

    function _setDrawPayoutBalanceOf(
        address _user,
        uint32 _drawId,
        uint256 _payout
    ) internal {
        userDrawPayouts[_user][_drawId] = _payout;
    }

    /**
     * @notice Sets IDrawCalculatorV3 reference for individual draw id.
     * @param _newCalculator  IDrawCalculatorV3 address
     */
    function _setDrawCalculator(IDrawCalculatorV3 _newCalculator) internal {
        require(address(_newCalculator) != address(0), "PrizeDistributorV2/calc-not-zero");
        drawCalculator = _newCalculator;

        emit DrawCalculatorSet(_newCalculator);
    }

    /**
     * @notice Transfer claimed draw(s) total payout to user.
     * @param _to      User address
     * @param _amount  Transfer amount
     */
    function _awardPayout(address _to, uint256 _amount) internal {
        token.safeTransferFrom(vault, _to, _amount);
    }

}
