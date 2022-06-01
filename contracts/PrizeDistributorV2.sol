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
     * @param pickIndices Pick indices for draw
     */
    event ClaimedDraw(
        address indexed user,
        uint32 indexed drawId,
        uint256 payout,
        uint64[] pickIndices
    );

    /**
     * @notice Emit when IDrawCalculatorV3 is set.
     * @param caller Address who has set the new DrawCalculator
     * @param calculator IDrawCalculatorV3 address
     */
    event DrawCalculatorSet(address indexed caller, IDrawCalculatorV3 indexed calculator);

    /**
     * @notice Emit when Token is set.
     * @param token Token address
     */
    event TokenSet(IERC20 indexed token);

    /**
     * @notice Emit when ERC20 tokens are withdrawn.
     * @param token  ERC20 token transferred
     * @param to     Address that received funds
     * @param amount Amount of tokens transferred
     */
    event ERC20Withdrawn(IERC20 indexed token, address indexed to, uint256 amount);

    /* ============ Global Variables ============ */

    /// @notice IDrawCalculatorV3 address
    IDrawCalculatorV3 internal drawCalculator;

    /// @notice Token address
    IERC20 internal immutable token;

    /// @notice Maps users => drawId => paid out balance
    mapping(address => mapping(uint256 => uint256)) internal userDrawPayouts;

    /// @notice The tokenVault that stores the prize tokens
    address public tokenVault;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs PrizeDistributorV2 smart contract.
     * @param _owner Contract owner address
     * @param _token Address of the token being used to pay out prizes
     * @param _drawCalculator Address of the DrawCalculatorV3 contract which computes draw payouts
     * @param _tokenVault Address of the TokenVault contract that holds the `token` being used to pay out prizes
     */
    constructor(
        address _owner,
        IERC20 _token,
        IDrawCalculatorV3 _drawCalculator,
        address _tokenVault
    ) Ownable(_owner) {
        require(_owner != address(0), "PDistV2/owner-not-zero-address");
        require(address(_token) != address(0), "PDistV2/token-not-zero-address");

        _setDrawCalculator(_drawCalculator);

        token = _token;
        tokenVault = _tokenVault;

        emit TokenSet(_token);
    }

    /* ============ External Functions ============ */

    /**
     * @notice Claim prize payout(s) by submitting valid drawId(s) and winning pick indice(s). The user address
               is used as the "seed" phrase to generate random numbers.
     * @dev    The claim function is public and any wallet may execute claim on behalf of another user.
               Prizes are always paid out to the designated user account and not the caller (msg.sender).
               Claiming prizes is not limited to a single transaction. Reclaiming can be executed
               subsequentially if an "optimal" prize was not included in previous claim pick indices. The
               payout difference for the new claim is calculated during the award process and transfered to user.
     * @param _ticket Address of the Ticket to claim prizes for
     * @param _user Address of the user to claim rewards for. Does NOT need to be msg.sender
     * @param _drawIds Draw IDs from global DrawBuffer reference
     * @param _drawPickIndices Pick indices for each drawId
     * @return Total claim payout. May include calculations from multiple draws.
     */
    function claim(
        ITicket _ticket,
        address _user,
        uint32[] calldata _drawIds,
        uint64[][] calldata _drawPickIndices
    ) external returns (uint256) {
        uint256 totalPayout;

        (uint256[] memory drawPayouts, ) = drawCalculator.calculate(
            _ticket,
            _user,
            _drawIds,
            _drawPickIndices
        );

        uint256 drawPayoutsLength = drawPayouts.length;

        for (uint256 payoutIndex = 0; payoutIndex < drawPayoutsLength; payoutIndex++) {
            uint32 drawId = _drawIds[payoutIndex];
            uint256 payout = drawPayouts[payoutIndex];
            uint256 oldPayout = _getDrawPayoutBalanceOf(_user, drawId);
            uint256 payoutDiff = 0;

            // helpfully short-circuit, in case the user screwed something up.
            require(payout > oldPayout, "PDistV2/zero-payout");

            unchecked {
                payoutDiff = payout - oldPayout;
            }

            _setDrawPayoutBalanceOf(_user, drawId, payout);

            totalPayout += payoutDiff;

            emit ClaimedDraw(_user, drawId, payoutDiff, _drawPickIndices[payoutIndex]);
        }

        _awardPayout(_user, totalPayout);

        return totalPayout;
    }

    /**
     * @notice Transfer ERC20 tokens out of contract to recipient address.
     * @dev Only callable by contract owner or manager.
     * @param _erc20Token Address of the ERC20 token to transfer
     * @param _to Address of the recipient of the tokens
     * @param _amount Amount of tokens to transfer
     * @return true if operation is successful.
     */
    function withdrawERC20(
        IERC20 _erc20Token,
        address _to,
        uint256 _amount
    ) external onlyManagerOrOwner returns (bool) {
        require(_to != address(0), "PDistV2/to-not-zero-address");
        require(address(_erc20Token) != address(0), "PDistV2/ERC20-not-zero-address");

        _erc20Token.safeTransfer(_to, _amount);

        emit ERC20Withdrawn(_erc20Token, _to, _amount);

        return true;
    }

    /**
     * @notice Read global DrawCalculator address.
     * @return IDrawCalculatorV3
     */
    function getDrawCalculator() external view returns (IDrawCalculatorV3) {
        return drawCalculator;
    }

    /**
     * @notice Get the amount that a user has already been paid out for a draw
     * @param _user User address
     * @param _drawId Draw ID
     */
    function getDrawPayoutBalanceOf(address _user, uint32 _drawId) external view returns (uint256) {
        return _getDrawPayoutBalanceOf(_user, _drawId);
    }

    /**
     * @notice Read global Token address.
     * @return IERC20
     */
    function getToken() external view returns (IERC20) {
        return token;
    }

    /**
     * @notice Sets DrawCalculator reference contract.
     * @param _newCalculator DrawCalculator address
     * @return New DrawCalculator address
     */
    function setDrawCalculator(IDrawCalculatorV3 _newCalculator)
        external
        onlyManagerOrOwner
        returns (IDrawCalculatorV3)
    {
        _setDrawCalculator(_newCalculator);
        return _newCalculator;
    }

    /* ============ Internal Functions ============ */

    /**
     * @notice Get payout balance of a user for a draw ID.
     * @param _user Address of the user to get payout balance for
     * @param _drawId Draw ID to get payout balance for
     * @return Draw ID payout balance
     */
    function _getDrawPayoutBalanceOf(address _user, uint32 _drawId)
        internal
        view
        returns (uint256)
    {
        return userDrawPayouts[_user][_drawId];
    }

    /**
     * @notice Set payout balance for a user and draw ID.
     * @param _user Address of the user to set payout balance for
     * @param _drawId Draw ID to set payout balance for
     * @param _payout Payout amount to set
     */
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
        require(address(_newCalculator) != address(0), "PDistV2/calc-not-zero-address");
        drawCalculator = _newCalculator;

        emit DrawCalculatorSet(msg.sender, _newCalculator);
    }

    /**
     * @notice Transfer claimed draw(s) total payout to user.
     * @param _to Address of the user to award payout to
     * @param _amount Amount of `token` to transfer
     */
    function _awardPayout(address _to, uint256 _amount) internal {
        token.safeTransferFrom(tokenVault, _to, _amount);
    }
}
