// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./import/prize-strategy/PrizeSplit.sol";
import "./import/prize-strategy/PeriodicPrizeStrategy.sol";
import "./ClaimableDraw.sol";

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
  */
  event Claimed (
    address indexed user,
    uint256 award,
    address token
  );

  /**
    * @notice Emit when the smart contract is initialized.
  */
  event ClaimableDrawPrizeStrategyInitialized (
    ClaimableDraw indexed claimableDraw
  );
  
  /**
    * @notice Emit when the smart contract is initialized.
  */
  event ClaimableDrawSet (
    ClaimableDraw indexed claimableDraw
  );

  /**
    * @notice Initialize the claimable draw prize strategy smart contract.
    *
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
  ) public initializer {
    __Ownable_init();

    IERC20Upgradeable[] memory _externalErc20Awards;

    PeriodicPrizeStrategy.initialize(
      _prizePeriodStart,
      _prizePeriodSeconds,
      _prizePool,
      _ticket,
      _sponsorship,
      _rng,
      _externalErc20Awards
    );

    claimableDraw = _claimableDraw;

    emit ClaimableDrawPrizeStrategyInitialized(_claimableDraw);
  }

  /**
    * @notice Set the external claimable draw contract. 
    *
    * @param _claimableDraw    Address of user
  */
  function setClaimableDraw(ClaimableDraw _claimableDraw) external onlyOwner returns (ClaimableDraw) {
    require(address(_claimableDraw) != address(0), "ClaimableDraw/claimable-draw-not-zero-address");
    require(_claimableDraw != claimableDraw, "ClaimableDraw/existing-claimable-draw-address");
    
    emit ClaimableDrawSet(_claimableDraw);
    
    return claimableDraw = _claimableDraw;

  }

  /**
    * @notice Set the external claimable draw contract. 
    *
    * @param user  Address of user
    * @param drawIds  Nested array of drawsIds
    * @param drawCalculators  Array draw calculator addresses
    * @param data  Pick indices for target draw
  */
  function claim(address user, uint256[][] calldata drawIds, IDrawCalculator[] calldata drawCalculators, bytes calldata data) external returns (uint256){
    address _ticket = address(ticket); // single SLOAD

    // Calculate the total payout using the processed draw ids and associated draw calculators addresses. 
    uint256 totalPayout = claimableDraw.claim(user, drawIds, drawCalculators, data);

    // Award user the with the total claim payout.
    prizePool.award(user, totalPayout, address(ticket));

    emit Claimed(user, totalPayout, _ticket);

    return totalPayout;
  }

  function _distribute(uint256 randomNumber) internal override virtual {
    uint256 prize = prizePool.captureAwardBalance();
    prize = _distributePrizeSplits(prize);

    uint256 timestamp = block.timestamp;
    claimableDraw.createDraw(randomNumber, timestamp, prize);
  }

  function _awardPrizeSplitAmount(address target, uint256 amount, uint8 tokenIndex) internal override {
    _awardToken(target, amount, tokenIndex);
  }

}