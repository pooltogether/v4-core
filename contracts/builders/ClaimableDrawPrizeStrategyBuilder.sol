// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./ControlledTokenBuilder.sol";
import "../ClaimableDrawProxyFactory.sol";
import "../ClaimableDrawPrizeStrategyProxyFactory.sol";
import "../TsunamiDrawCalculatorProxyFactory.sol";
import "@pooltogether/pooltogether-rng-contracts/contracts/RNGInterface.sol";

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
    PrizePool _prizePool,
    ClaimableDrawBuilderConfig memory _prizeStrategyConfig,
    TsunamiDrawCalculator.DrawSettings memory _calculatorDrawSettings,
    uint8 _decimals,
    address _owner
  ) external returns (ClaimableDrawPrizeStrategy) {
    ClaimableDrawPrizeStrategy _cdprz = claimableDrawPrizeStrategyProxyFactory.create();

    // Internal function to avoid stack to deep error.
    _initializeClaimableDraw(_prizePool, _cdprz, _prizeStrategyConfig, _calculatorDrawSettings, _decimals);

    _cdprz.setPrizeSplits(_prizeStrategyConfig.prizeSplits);
    _cdprz.transferOwnership(_owner);
    emit ClaimableDrawBuilderCreated(address(_cdprz));

    return _cdprz;
  }

  function _initializeClaimableDraw(
    PrizePool _prizePool,
    ClaimableDrawPrizeStrategy _cdprz,
    ClaimableDrawBuilderConfig memory _prizeStrategyConfig,
    TsunamiDrawCalculator.DrawSettings memory _calculatorDrawSettings,
    uint8 _decimals
  ) internal {
    ClaimableDraw _cd = claimableDrawProxyFactory.create();
    TsunamiDrawCalculator _calculator = tsunamiDrawCalculatorProxyFactory.create();

    Ticket _ticket = _createTicket(
      _prizeStrategyConfig.ticketName,
      _prizeStrategyConfig.ticketSymbol,
      _decimals,
      _prizePool
    );

    ControlledToken sponsorship = _createSponsorship(
      _prizeStrategyConfig.sponsorshipName,
      _prizeStrategyConfig.sponsorshipSymbol,
      _decimals,
      _prizePool
    );

    _cdprz.initializeClaimableDraw(
      _prizeStrategyConfig.prizePeriodStart,
      _prizeStrategyConfig.prizePeriodSeconds,
      _prizePool,
      _ticket,
      sponsorship,
      _prizeStrategyConfig.rngService,
      _cd
    );

    // Initialize ClaimableDraw
    _cd.initialize(address(_cdprz), _calculator);

    // Initialize Calculator
    _calculator.initialize(TicketInterface(address(_ticket)), _calculatorDrawSettings);
  }

  function _createTicket(
    string memory _name,
    string memory _token,
    uint8 _decimals,
    PrizePool _prizePool
  ) internal returns (Ticket) {
    return controlledTokenBuilder.createTicket(
      ControlledTokenBuilder.ControlledTokenConfig(
        _name,
        _token,
        _decimals,
        address(_prizePool)
      )
    );
  }

  function _createSponsorship(
    string memory _name,
    string memory _token,
    uint8 _decimals,
    PrizePool _prizePool
  ) internal returns (ControlledToken) {
    return controlledTokenBuilder.createControlledToken(
      ControlledTokenBuilder.ControlledTokenConfig(
        _name,
        _token,
        _decimals,
        address(_prizePool)
      )
    );
  }
}
