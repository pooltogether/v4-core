// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;
import "@pooltogether/owner-manager-contracts/contracts/Manageable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IPrizeFlush.sol";

/**
  * @title  PoolTogether V4 PrizeFlush
  * @author PoolTogether Inc Team
  * @notice The PrizeFlush is a helper library to facilate interest distribution. 
*/
contract PrizeFlush is IPrizeFlush, Manageable {

  /// @notice Static destination for captured interest
  address   internal destination;
  
  /// @notice IReserve address 
  IReserve  internal reserve;
  
  /// @notice IStrategy address 
  IStrategy internal strategy;

  /* ============ Events ============ */

  /**
    * @notice Emit when contract deployed.
    * @param reserve IReserve
    * @param strategy IStrategy
    * 
   */
  event Deployed(address destination, IReserve reserve, IStrategy strategy);

  /* ============ Constructor ============ */    

  /**
    * @notice Set owner, reserve and strategy when deployed.
    * @param _owner       address
    * @param _destination address
    * @param _strategy    IStrategy
    * @param _reserve     IReserve
    * 
   */
  constructor(address _owner, address _destination, IStrategy _strategy, IReserve _reserve) Ownable(_owner) {
    destination  = _destination;
    strategy     = _strategy;
    reserve      = _reserve;

    // Emit Deploy State 
    emit Deployed(_destination, _reserve, _strategy);
  }

  /* ============ External Functions ============ */

  // @inheritdoc 
  function getDestination() external view override returns (address) {
    return destination;
  }
  
  function getReserve() external view override returns (IReserve) {
    return reserve;
  }

  function getStrategy() external view override returns (IStrategy) {
    return strategy;
  }

  function setDestination(address _destination) external onlyOwner override returns (address) {
    require(_destination != address(0), "Flush/destination-not-zero-address");
    destination = _destination;
    return _destination;
  }
  
  function setReserve(IReserve _reserve) external override onlyOwner returns (IReserve) {
    require(address(_reserve) != address(0), "Flush/reserve-not-zero-address");
    reserve = _reserve;
    return reserve;
  }

  function setStrategy(IStrategy _strategy) external override onlyOwner returns (IStrategy) {
    require(address(_strategy) != address(0), "Flush/strategy-not-zero-address");
    strategy = _strategy;
    return _strategy;
  }

  /**
    * @notice Migrate interest from PrizePool to DrawPrizes in single transaction.
    * @dev    Captures interest, checkpoint data and transfers tokens to final destination.
    * 
   */
  function flush() external override onlyManagerOrOwner returns (bool) {
    strategy.distribute();

    // After captured interest transferred to Strategy.PrizeSplits[]: [Reserve, Other]
    // transfer the Reserve balance directly to the DrawPrizes (destination) address.
    IReserve _reserve = reserve;
    IERC20 _token     = _reserve.getToken();
    uint256 _amount   = _token.balanceOf(address(_reserve));

    if(_amount > 0) {
      // Create checkpoint and transfers new total balance to DrawPrizes
      _reserve.withdrawTo(destination, _token.balanceOf(address(_reserve)));

      emit Flushed(destination, _amount);
    }
  }

}