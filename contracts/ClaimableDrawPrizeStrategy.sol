// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./import/prize-strategy/PrizeSplit.sol";
import "./import/prize-strategy/PeriodicPrizeStrategy.sol";
import "./ClaimableDraw.sol";
import "./interfaces/TicketInterface.sol";

contract ClaimableDrawPrizeStrategy is Initializable, 
                                       OwnableUpgradeable, 
                                       PeriodicPrizeStrategy, 
                                       PrizeSplit {
 /**
    * @notice External claimable draw contract responsible for handling persistent data even when prize strategy may be updated.
  */
  ClaimableDraw public claimableDraw;

  /**
    * @notice Emit when a user has claimed award(s)
    * @param user  Address of user receiving awarded tickets
    * @param award Total tickets minted after calculating award amount
    * @param token Address of token (Ticket) being minted
  */
  event Claimed (
    address indexed user,
    uint256 award,
    address token
  );

  /**
    * @notice Emit when the smart contract is initialized.
    * @param claimableDraw  Address of the ClaimableDraw used to manage user's claim history
  */
  event ClaimableDrawPrizeStrategyInitialized (
    ClaimableDraw indexed claimableDraw
  );
  
  /**
    * @notice Emit when a new ClaimableDraw is set.
    * @param claimableDraw  Address of the ClaimableDraw used to manage a user's draw claim history
  */
  event ClaimableDrawSet (
    ClaimableDraw indexed claimableDraw
  );

  /**
    * @notice Initialize the claimable draw prize strategy smart contract.
    *
    * @param _prizePeriodStart The starting timestamp of the prize period.
    * @param _prizePeriodSeconds The duration of the prize period in seconds
    * @param _prizePool The prize pool to award
    * @param _ticket The ticket to use to draw winners
    * @param _sponsorship The sponsorship token
    * @param _rng The RNG service to use
    * @param _claimableDraw  Address of claimable draw
  */
  function initializeClaimableDraw (
    uint256 _prizePeriodStart,
    uint256 _prizePeriodSeconds,
    PrizePool _prizePool,
    TicketInterface _ticket,
    IERC20Upgradeable _sponsorship,
    RNGInterface _rng,
    ClaimableDraw _claimableDraw
  ) external initializer returns (bool) {
    __Ownable_init();
    IERC20Upgradeable[] memory _externalErc20Awards;
    PeriodicPrizeStrategy.initialize(
      _prizePeriodStart,
      _prizePeriodSeconds,
      _prizePool,
      TicketInterface(address(_ticket)),
      _sponsorship,
      _rng,
      _externalErc20Awards
    );

    claimableDraw = _claimableDraw;

    emit ClaimableDrawPrizeStrategyInitialized(_claimableDraw);

    return true;
  }

  /**
    * @notice Sets the claimable draw contract. 
    * @dev    Sets the ClaimableDraw used to manage a user's draw claim history
    *
    * @param _claimableDraw Address of  ClaimableDraw smart contract
  */
  function setClaimableDraw(ClaimableDraw _claimableDraw) external onlyOwner returns (ClaimableDraw) {
    require(address(_claimableDraw) != address(0), "ClaimableDraw/claimable-draw-not-zero-address");
    require(_claimableDraw != claimableDraw, "ClaimableDraw/existing-claimable-draw-address");
    
    emit ClaimableDrawSet(_claimableDraw);
    
    return claimableDraw = _claimableDraw;

  }

  /**
    * @notice Claims total award payout using an array of draw ids and specific pick indices for each draw.
    * @dev    Mints tickets to a target after calculating the total payout using the external ClaimableDraw smart contract.
    *
    * @param user             Address of user
    * @param drawIds          Nested array of drawsIds
    * @param drawCalculators  Array of draw calculator addresses correlated to draw ids
    * @param data             Nested array of pick indices (uint256[][][]) correlated to the draw ids
  */
  function claim(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes[] calldata data) external returns (uint256){
    address _ticket = address(ticket); // single SLOAD

    // Calculate the total payout using the processed draw ids and associated draw calculators addresses. 
    uint256 totalPayout = claimableDraw.claim(user, drawIds, drawCalculators, data);

    // Award user with the total claim payout.
    prizePool.award(user, totalPayout, _ticket);

    emit Claimed(user, totalPayout, _ticket);

    return totalPayout;
  }

  /**
    * @notice Capture an award balance and create new draw with randomly generated number, block timestamp and prize total. 
    * @dev    Claims total award payout using an array of draw ids and specific pick indices for each draw
    *
    * @param randomNumber Randomly generated number
  */
  function _distribute(uint256 randomNumber) internal override virtual {
    uint256 prize = prizePool.captureAwardBalance();
    prize = _distributePrizeSplits(prize);
    claimableDraw.createDraw(randomNumber, uint32(block.timestamp), prize);
  }

  /**
    * @notice Capture an award balance and create new draw with randomly generated number, block timestamp and prize total. 
    * @dev    Claims total award payout using an array of draw ids and specific pick indices for each draw
    *
    * @param target Recipient of prize split award amount
    * @param amount Token amount minted to prize split recipient 
    * @param tokenIndex Index (0 or 1) of a token in the prizePool.tokens mapping
  */
  function _awardPrizeSplitAmount(address target, uint256 amount, uint8 tokenIndex) internal override {
    _awardToken(target, amount, tokenIndex);
  }

}