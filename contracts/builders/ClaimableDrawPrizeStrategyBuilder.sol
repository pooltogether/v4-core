// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./ControlledTokenBuilder.sol";
import "../ClaimableDrawProxyFactory.sol";
import "../ClaimableDrawPrizeStrategyProxyFactory.sol";
import "../TsunamiDrawCalculatorProxyFactory.sol";
import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";

/* solium-disable security/no-block-members */
contract ClaimableDrawPrizeStrategyBuilder {

  event ClaimableDrawBuilderCreated(address indexed prizeStrategy);

  struct ClaimableDrawBuilderConfig {
    RNGInterface rngService;
    uint256 prizePeriodStart;
    uint256 prizePeriodSeconds;
    string ticketName;
    string ticketSymbol;
    string sponsorshipName;
    string sponsorshipSymbol;
    uint256 ticketCreditLimitMantissa;
    uint256 ticketCreditRateMantissa;
    ClaimableDrawPrizeStrategy.PrizeSplitConfig[] prizeSplits;
    bool splitExternalErc20Awards;
  }

  ClaimableDrawProxyFactory public claimableDrawProxyFactory;
  ClaimableDrawPrizeStrategyProxyFactory public claimableDrawPrizeStrategyProxyFactory;
  TsunamiDrawCalculatorProxyFactory public tsunamiDrawCalculatorProxyFactory;
  ControlledTokenBuilder public controlledTokenBuilder;

  constructor (
    ClaimableDrawProxyFactory _claimableDrawProxyFactory,
    ClaimableDrawPrizeStrategyProxyFactory _claimableDrawPrizeStrategyProxyFactory,
    TsunamiDrawCalculatorProxyFactory _tsunamiDrawCalculatorProxyFactory,
    ControlledTokenBuilder _controlledTokenBuilder
  ) {
    require(address(_claimableDrawProxyFactory) != address(0), "ClaimableDrawBuilderBuilder/claimableDrawProxyFactory-not-zero");
    require(address(_claimableDrawPrizeStrategyProxyFactory) != address(0), "ClaimableDrawBuilderBuilder/claimableDrawPrizeStrategyProxyFactory-not-zero");
    require(address(_tsunamiDrawCalculatorProxyFactory) != address(0), "ClaimableDrawBuilderBuilder/tsunamiDrawCalculatorProxyFactory-not-zero");
    require(address(_controlledTokenBuilder) != address(0), "ClaimableDrawBuilderBuilder/token-builder-not-zero");
    claimableDrawProxyFactory = _claimableDrawProxyFactory;
    claimableDrawPrizeStrategyProxyFactory = _claimableDrawPrizeStrategyProxyFactory;
    tsunamiDrawCalculatorProxyFactory = _tsunamiDrawCalculatorProxyFactory;
    controlledTokenBuilder = _controlledTokenBuilder;
  }

  function createClaimableDraw(
    PrizePool prizePool,
    ClaimableDrawBuilderConfig memory prizeStrategyConfig,
    TsunamiDrawCalculator.DrawSettings memory calculatorDrawSettings,
    uint8 decimals,
    address owner
  ) external returns (ClaimableDrawPrizeStrategy) {
    ClaimableDrawPrizeStrategy cdprz = claimableDrawPrizeStrategyProxyFactory.create();

    // Internal function to avoid stack to deep error. 
    initializeClaimableDraw(prizePool, cdprz, prizeStrategyConfig, calculatorDrawSettings, decimals);

    cdprz.setPrizeSplits(prizeStrategyConfig.prizeSplits);
    cdprz.transferOwnership(owner);
    emit ClaimableDrawBuilderCreated(address(cdprz));

    return cdprz;
  }

  function initializeClaimableDraw(
    PrizePool prizePool,
    ClaimableDrawPrizeStrategy cdprz, 
    ClaimableDrawBuilderConfig memory prizeStrategyConfig, 
    TsunamiDrawCalculator.DrawSettings memory calculatorDrawSettings,
    uint8 decimals
  ) internal {
    ClaimableDraw cd = claimableDrawProxyFactory.create();
    TsunamiDrawCalculator calculator = tsunamiDrawCalculatorProxyFactory.create();

    Ticket ticket = _createTicket(
      prizeStrategyConfig.ticketName,
      prizeStrategyConfig.ticketSymbol,
      decimals,
      prizePool
    );

    ControlledToken sponsorship = _createSponsorship(
      prizeStrategyConfig.sponsorshipName,
      prizeStrategyConfig.sponsorshipSymbol,
      decimals,
      prizePool
    );

    cdprz.initializeClaimableDraw(
      prizeStrategyConfig.prizePeriodStart,
      prizeStrategyConfig.prizePeriodSeconds,
      prizePool,
      ticket,
      sponsorship,
      prizeStrategyConfig.rngService,
      cd
    );

    // Initialize ClaimableDraw
    cd.initialize(address(cdprz), calculator);
    
    // Initialize Calculator
    calculator.initialize(ITicketTwab(address(ticket)), calculatorDrawSettings);

  }

  function _createTicket(
    string memory name,
    string memory token,
    uint8 decimals,
    PrizePool prizePool
  ) internal returns (Ticket) {
    return controlledTokenBuilder.createTicket(
      ControlledTokenBuilder.ControlledTokenConfig(
        name,
        token,
        decimals,
        prizePool
      )
    );
  }

  function _createSponsorship(
    string memory name,
    string memory token,
    uint8 decimals,
    PrizePool prizePool
  ) internal returns (ControlledToken) {
    return controlledTokenBuilder.createControlledToken(
      ControlledTokenBuilder.ControlledTokenConfig(
        name,
        token,
        decimals,
        prizePool
      )
    );
  }
}
