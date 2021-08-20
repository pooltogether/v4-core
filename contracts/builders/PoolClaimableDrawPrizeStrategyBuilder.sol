// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import "./ClaimableDrawPrizeStrategyBuilder.sol";
import "../import/registry/RegistryInterface.sol";
import "../import/prize-pool/compound/CompoundPrizePoolProxyFactory.sol";

contract PoolClaimableDrawPrizeStrategyBuilder {
  using SafeCastUpgradeable for uint256;

  event CompoundPrizePoolWithClaimableDrawCreated(
    CompoundPrizePool indexed prizePool,
    ClaimableDrawPrizeStrategy indexed prizeStrategy
  );

  /// @notice The configuration used to initialize the Compound Prize Pool
  struct CompoundPrizePoolConfig {
    CTokenInterface cToken;
    uint256 maxExitFeeMantissa;
  }

  RegistryInterface public reserveRegistry;
  CompoundPrizePoolProxyFactory public compoundPrizePoolProxyFactory;
  ClaimableDrawPrizeStrategyBuilder public claimableDrawPrizeStrategyBuilder;

  constructor (
    RegistryInterface _reserveRegistry,
    CompoundPrizePoolProxyFactory _compoundPrizePoolProxyFactory,
    ClaimableDrawPrizeStrategyBuilder _claimableDrawPrizeStrategyBuilder
  ) {
    require(address(_reserveRegistry) != address(0), "GlobalBuilder/reserveRegistry-not-zero");
    require(address(_compoundPrizePoolProxyFactory) != address(0), "GlobalBuilder/compoundPrizePoolProxyFactory-not-zero");
    require(address(_claimableDrawPrizeStrategyBuilder) != address(0), "GlobalBuilder/claimableDrawPrizeStrategyBuilder-not-zero");
    reserveRegistry = _reserveRegistry;
    compoundPrizePoolProxyFactory = _compoundPrizePoolProxyFactory;
    claimableDrawPrizeStrategyBuilder = _claimableDrawPrizeStrategyBuilder;
  }

  function createCompoundClaimableDrawPrizeStrategy(
    CompoundPrizePoolConfig memory prizePoolConfig,
    ClaimableDrawPrizeStrategyBuilder.ClaimableDrawBuilderConfig memory prizeStrategyConfig,
    TsunamiDrawCalculator.DrawSettings memory calculatorDrawSettings,
    uint8 decimals
  ) external returns (CompoundPrizePool) {
    CompoundPrizePool prizePool = compoundPrizePoolProxyFactory.create();
    ClaimableDrawPrizeStrategy prizeStrategy = claimableDrawPrizeStrategyBuilder.createClaimableDraw(
      prizePool,
      prizeStrategyConfig,
      calculatorDrawSettings,
      decimals,
      msg.sender
    );
    prizePool.initialize(
      reserveRegistry,
      _tokens(prizeStrategy),
      prizePoolConfig.maxExitFeeMantissa,
      CTokenInterface(prizePoolConfig.cToken)
    );
    prizePool.setPrizeStrategy(prizeStrategy);
    prizePool.setCreditPlanOf(
      address(prizeStrategy.ticket()),
      prizeStrategyConfig.ticketCreditRateMantissa.toUint128(),
      prizeStrategyConfig.ticketCreditLimitMantissa.toUint128()
    );
    prizePool.transferOwnership(msg.sender);
    emit CompoundPrizePoolWithClaimableDrawCreated(prizePool, prizeStrategy);
    return prizePool;
  }

 
  function _tokens(ClaimableDrawPrizeStrategy _claimableDrawPrizeStrategy) internal view returns (ControlledTokenInterface[] memory) {
    ControlledTokenInterface[] memory tokens = new ControlledTokenInterface[](2);
    tokens[0] = ControlledTokenInterface(address(_claimableDrawPrizeStrategy.sponsorship()));
    tokens[1] = ControlledTokenInterface(address(_claimableDrawPrizeStrategy.ticket()));
    return tokens;
  }

}
