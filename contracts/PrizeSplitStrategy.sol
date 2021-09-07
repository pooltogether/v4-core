// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "./prize-pool/PrizePool.sol";
import "./prize-strategy/PrizeSplit.sol";

contract PrizeSplitStrategy is Initializable, PrizeSplit {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /**
    * @notice Linked PrizePool smart contract responsible for awarding tokens.
  */
  PrizePool public prizePool;

   /**
    * @notice Emit when a strategy captures award amount from PrizePool
    * @param totalPrizeCaptured  Total prize captured
  */
  event Distribute(
    uint256 totalPrizeCaptured
  );

  /**
    * @notice Emit when a prize split is awarded
    * @param user          User address
    * @param prizeAwarded  Token prize amount
    * @param token         Token minted address
  */
  event PrizeSplitAwarded(
    address indexed user, 
    uint256 prizeAwarded,
    address indexed token 
  );

  /**
    * @notice Initialize the PrizeSplitStrategy smart contract.
    * @param _prizePool PrizePool contract address
  */
  function initialize (
    PrizePool _prizePool
  ) external initializer {
    __Ownable_init();
    require(address(_prizePool) != address(0), "PrizeSplitStrategy/prize-pool-not-zero");
    prizePool = _prizePool;
  }

  /* ============ Public Functions ============ */
  /**
    * @notice Capture the award balance and distribute to prize splits.
    * @dev    Capture the award balance and award tokens using the linked PrizePool.
    * @return Total prize amount using the prizePool.captureAwardBalance()
  */
  function distribute() external returns (uint256) {
    require(_prizeSplits.length > 0, "PrizeSplitStrategy/prize-split-unavailable");

    // Ensure 100% of the captured award balance is distributed.
    uint256 totalPercentage = _totalPrizeSplitPercentageAmount();
    require(totalPercentage == 1000, "PrizeSplitStrategy/invalid-prizesplit-percentage-total");

    uint256 prize = prizePool.captureAwardBalance();
    _distributePrizeSplits(prize);
    emit Distribute(prize);
    return prize;
  }

  /* ============ Internal Functions ============ */
  
  /**
    * @notice Award ticket or sponsorship tokens to prize split recipient.
    * @dev Award ticket or sponsorship tokens to prize split recipient via the linked PrizePool contract.
    * @param user Recipient of minted tokens
    * @param amount Amount of minted tokens
    * @param tokenIndex Index (0 or 1) of a token in the prizePool.tokens mapping
  */
  function _awardPrizeSplitAmount(address user, uint256 amount, uint8 tokenIndex) override internal {
    ControlledTokenInterface[] memory _controlledTokens = prizePool.tokens();
    require(tokenIndex <= _controlledTokens.length, "PrizeSplitStrategy/invalid-token-index");
    ControlledTokenInterface _token = _controlledTokens[tokenIndex];
    emit PrizeSplitAwarded(user, amount, address(_token));
    prizePool.award(user, amount, address(_token));
  }

}