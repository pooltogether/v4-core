// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IDrawHistory.sol";
import "./IDrawCalculator.sol";
import "./IDrawBeacon.sol";


interface IDrawPrize {
    /**
     * @notice Emitted when a user has claimed N draw payouts.
     * @param user        User address receiving draw claim payouts
     * @param drawId      Draw id that was paid out
     * @param payout Payout for draw
     */
    event ClaimedDraw(address indexed user, uint32 indexed drawId, uint256 payout);

    /**
     * @notice Emitted when a DrawCalculator is set
     * @param calculator DrawCalculator address
     */
    event DrawCalculatorSet(IDrawCalculator indexed calculator);

    /**
     * @notice Emitted when a global Ticket variable is set.
     * @param token Token address
     */
    event TokenSet(IERC20 indexed token);

    /**
     * @notice Emitted when ERC20 tokens are withdrawn
     * @param token ERC20 token transferred.
     * @param to Address that received funds.
     * @param amount Amount of tokens transferred.
     */
    event ERC20Withdrawn(IERC20 indexed token, address indexed to, uint256 amount);

    /**
     * @notice Claim a user token payouts via a collection of draw ids and pick indices.
     * @param user    Address of user to claim awards for. Does NOT need to be msg.sender
     * @param drawIds Draw IDs from global DrawHistory reference
     * @param data    The data to pass to the draw calculator
     * @return Actual claim payout.  If the user has previously claimed a draw, this may be less.
     */
    function claim(
        address user,
        uint32[] calldata drawIds,
        bytes calldata data
    ) external returns (uint256);

    /**
     * @notice Read DrawCalculator
     * @return IDrawCalculator
     */
    function getDrawCalculator() external view returns (IDrawCalculator);

    /**
     * @notice Get the amount that a user has already been paid out for a draw
     * @param user   User address
     * @param drawId Draw ID
     */
    function getDrawPayoutBalanceOf(address user, uint32 drawId) external view returns (uint256);

    /**
     * @notice Read global Ticket variable.
     * @return IERC20
     */
    function getToken() external view returns (IERC20);

    /**
     * @notice Sets DrawCalculator reference for individual draw id.
     * @param _newCalculator  DrawCalculator address
     * @return New DrawCalculator address
     */
    function setDrawCalculator(IDrawCalculator _newCalculator) external returns (IDrawCalculator);

    function withdrawERC20(
        IERC20 _erc20Token,
        address _to,
        uint256 _amount
    ) external returns (bool);
}
