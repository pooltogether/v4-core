// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "./ControlledTokenBuilder.sol";
import "../ClaimableDrawProxyFactory.sol";
import "../ClaimableDrawPrizeStrategyProxyFactory.sol";
import "../import/prize-strategy/PrizeSplit.sol";

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
  ControlledTokenBuilder public controlledTokenBuilder;

  constructor (
    ClaimableDrawProxyFactory _claimableDrawProxyFactory,
    ClaimableDrawPrizeStrategyProxyFactory _claimableDrawPrizeStrategyProxyFactory,
    ControlledTokenBuilder _controlledTokenBuilder
  ) {
    require(address(_claimableDrawProxyFactory) != address(0), "ClaimableDrawBuilderBuilder/claimableDrawProxyFactory-not-zero");
    require(address(_claimableDrawPrizeStrategyProxyFactory) != address(0), "ClaimableDrawBuilderBuilder/claimableDrawPrizeStrategyProxyFactory-not-zero");
    require(address(_controlledTokenBuilder) != address(0), "ClaimableDrawBuilderBuilder/token-builder-not-zero");
    claimableDrawProxyFactory = _claimableDrawProxyFactory;
    claimableDrawPrizeStrategyProxyFactory = _claimableDrawPrizeStrategyProxyFactory;
    controlledTokenBuilder = _controlledTokenBuilder;
  }

  function createClaimableDrawBuilder(
    PrizePool prizePool,
    ClaimableDrawBuilderConfig memory prizeStrategyConfig,
    uint8 decimals,
    address owner
  ) external returns (ClaimableDrawPrizeStrategy) {
    ClaimableDraw cd = claimableDrawProxyFactory.create();
    ClaimableDrawPrizeStrategy cdprz = claimableDrawPrizeStrategyProxyFactory.create();

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

    cdprz.setPrizeSplits(prizeStrategyConfig.prizeSplits);

    if (prizeStrategyConfig.splitExternalErc20Awards) {
      cdprz.setSplitExternalErc20Awards(true);
    }

    cdprz.transferOwnership(owner);

    emit ClaimableDrawBuilderCreated(address(cdprz));

    return cdprz;
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
