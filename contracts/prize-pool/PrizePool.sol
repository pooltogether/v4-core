// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";

import "../external/compound/ICompLike.sol";
import "../interfaces/IPrizePool.sol";

/// @title Escrows assets and deposits them into a yield source.  Exposes interest to Prize Strategy.
///       Users deposit and withdraw from this contract to participate in Prize Pool.
/// @notice Accounting is managed using Controlled Tokens, whose mint and burn functions can only be called by this contract.
/// @dev Must be inherited to provide specific yield-bearing asset control, such as Compound cTokens
abstract contract PrizePool is IPrizePool, Ownable, ReentrancyGuard, IERC721Receiver {
  using SafeCast for uint256;
  using SafeERC20 for IERC20;
  using SafeERC20 for IERC721;
  using ERC165Checker for address;

  /// @notice Semver Version
  string constant public VERSION = "4.0.0";

  /// @dev Prize Pool ticket. Can only be set once by calling `setTicket()`.
  IControlledToken public override ticket;

  /// @dev The Prize Strategy that this Prize Pool is bound to.
  address public prizeStrategy;

  /// @dev The total amount per tokens a user can hold.
  mapping(address => uint256) public balanceCap;

  /// @dev The total amount of funds that the prize pool can hold.
  uint256 public liquidityCap;

  /// @dev the The awardable balance
  uint256 internal _currentAwardBalance;

  /// @notice Deploy the Prize Pool
  constructor () Ownable() ReentrancyGuard() {
    _setLiquidityCap(type(uint256).max);
  }

  /// @dev Returns the address of the underlying ERC20 asset
  /// @return The address of the asset
  function token() external override view returns (address) {
    return address(_token());
  }

  /// @dev Returns the total underlying balance of all assets. This includes both principal and interest.
  /// @return The underlying balance of assets
  function balance() external returns (uint256) {
    return _balance();
  }

  /// @dev Checks with the Prize Pool if a specific token type may be awarded as an external prize
  /// @param _externalToken The address of the token to check
  /// @return True if the token may be awarded, false otherwise
  function canAwardExternal(address _externalToken) external view returns (bool) {
    return _canAwardExternal(_externalToken);
  }

  /// @notice Deposit assets into the Prize Pool in exchange for tokens
  /// @param _to The address receiving the newly minted tokens
  /// @param _amount The amount of assets to deposit
  function depositTo(
    address _to,
    uint256 _amount
  )
    external override
    nonReentrant
    canAddLiquidity(_amount)
  {
    address _operator = _msgSender();

    require(_canDeposit(_operator, _amount), "PrizePool/exceeds-balance-cap");

    IControlledToken _ticket = ticket;

    _mint(_to, _amount, _ticket);

    _token().safeTransferFrom(_operator, address(this), _amount);
    _supply(_amount);

    emit Deposited(_operator, _to, _ticket, _amount);
  }

  /// @notice Withdraw assets from the Prize Pool.
  /// @param _from The address to redeem tokens from.
  /// @param _amount The _amount of tokens to redeem for assets.
  /// @return The actual amount redeemed.
  function withdrawFrom(
    address _from,
    uint256 _amount
  )
    external override
    nonReentrant
    returns (uint256)
  {
    IControlledToken _ticket = ticket;

    // burn the tickets
    _ticket.controllerBurnFrom(_msgSender(), _from, _amount);

    // redeem the tickets
    uint256 _redeemed = _redeem(_amount);

    _token().safeTransfer(_from, _redeemed);

    emit Withdrawal(_msgSender(), _from, _ticket, _amount, _redeemed);

    return _redeemed;
  }

  /// @notice Returns the balance that is available to award.
  /// @dev captureAwardBalance() should be called first
  /// @return The total amount of assets to be awarded for the current prize
  function awardBalance() external override view returns (uint256) {
    return _currentAwardBalance;
  }

  /// @notice Captures any available interest as award balance.
  /// @return The total amount of assets to be awarded for the current prize
  function captureAwardBalance() external override nonReentrant returns (uint256) {
    uint256 ticketTotalSupply = _ticketTotalSupply();

    // it's possible for the balance to be slightly less due to rounding errors in the underlying yield source
    uint256 currentBalance = _balance();
    uint256 totalInterest = (currentBalance > ticketTotalSupply) ? currentBalance - ticketTotalSupply : 0;
    uint256 unaccountedPrizeBalance = (totalInterest > _currentAwardBalance) ? totalInterest - _currentAwardBalance : 0;

    if (unaccountedPrizeBalance > 0) {
      _currentAwardBalance = _currentAwardBalance + unaccountedPrizeBalance;

      emit AwardCaptured(unaccountedPrizeBalance);
    }

    return _currentAwardBalance;
  }

  /// @notice Called by the prize strategy to award prizes.
  /// @dev The amount awarded must be less than the awardBalance()
  /// @param _to The address of the winner that receives the award
  /// @param _amount The amount of assets to be awarded
  function award(
    address _to,
    uint256 _amount
  )
    external override
    onlyPrizeStrategy
  {
    if (_amount == 0) {
      return;
    }

    require(_amount <= _currentAwardBalance, "PrizePool/award-exceeds-avail");
    _currentAwardBalance = _currentAwardBalance - _amount;

    IControlledToken _ticket = ticket;

    _mint(_to, _amount, _ticket);

    emit Awarded(_to, _ticket, _amount);
  }

  /// @notice Called by the Prize-Strategy to transfer out external ERC20 tokens
  /// @dev Used to transfer out tokens held by the Prize Pool.  Could be liquidated, or anything.
  /// @param _to Address of the winner that receives the award
  /// @param _externalToken Address of the external asset token being awarded
  /// @param _amount Amount of external assets to be awarded
  function transferExternalERC20(
    address _to,
    address _externalToken,
    uint256 _amount
  )
    external override
    onlyPrizeStrategy
  {
    if (_transferOut(_to, _externalToken, _amount)) {
      emit TransferredExternalERC20(_to, _externalToken, _amount);
    }
  }

  /// @notice Called by the Prize-Strategy to award external ERC20 prizes
  /// @dev Used to award any arbitrary tokens held by the Prize Pool
  /// @param _to Address of the winner that receives the award
  /// @param _externalToken Address of the external asset token being awarded
  /// @param _amount Amount of external assets to be awarded
  function awardExternalERC20(
    address _to,
    address _externalToken,
    uint256 _amount
  )
    external override
    onlyPrizeStrategy
  {
    if (_transferOut(_to, _externalToken, _amount)) {
      emit AwardedExternalERC20(_to, _externalToken, _amount);
    }
  }

  /// @notice Transfer out `amount` of `externalToken` to recipient `to`
  /// @dev Only awardable `externalToken` can be transferred out
  /// @param _to Recipient address
  /// @param _externalToken Address of the external asset token being transferred
  /// @param _amount Amount of external assets to be transferred
  /// @return True if transfer is successful
  function _transferOut(
    address _to,
    address _externalToken,
    uint256 _amount
  )
    internal
    returns (bool)
  {
    require(_canAwardExternal(_externalToken), "PrizePool/invalid-external-token");

    if (_amount == 0) {
      return false;
    }

    IERC20(_externalToken).safeTransfer(_to, _amount);

    return true;
  }

  /// @notice Called to mint controlled tokens.  Ensures that token listener callbacks are fired.
  /// @param _to The user who is receiving the tokens
  /// @param _amount The amount of tokens they are receiving
  /// @param _controlledToken The token that is going to be minted
  function _mint(address _to, uint256 _amount, IControlledToken _controlledToken) internal {
    _controlledToken.controllerMint(_to, _amount);
  }

  /// @notice Called by the prize strategy to award external ERC721 prizes
  /// @dev Used to award any arbitrary NFTs held by the Prize Pool
  /// @param to The address of the winner that receives the award
  /// @param externalToken The address of the external NFT token being awarded
  /// @param tokenIds An array of NFT Token IDs to be transferred
  function awardExternalERC721(
    address to,
    address externalToken,
    uint256[] calldata tokenIds
  )
    external override
    onlyPrizeStrategy
  {
    require(_canAwardExternal(externalToken), "PrizePool/invalid-external-token");

    if (tokenIds.length == 0) {
      return;
    }

    for (uint256 i = 0; i < tokenIds.length; i++) {
      try IERC721(externalToken).safeTransferFrom(address(this), to, tokenIds[i]){

      }
      catch(bytes memory error){
        emit ErrorAwardingExternalERC721(error);
      }

    }

    emit AwardedExternalERC721(to, externalToken, tokenIds);
  }

  /// @notice Allows the owner to set a balance cap per `token` for the pool.
  /// @dev If a user wins, his balance can go over the cap. He will be able to withdraw the excess but not deposit.
  /// @dev Needs to be called after deploying a prize pool to be able to deposit into it.
  /// @param _token Address of the token to set the balance cap for.
  /// @param _balanceCap New balance cap.
  /// @return True if new balance cap has been successfully set.
  function setBalanceCap(address _token, uint256 _balanceCap) external override onlyOwner returns (bool) {
    _setBalanceCap(_token, _balanceCap);
    return true;
  }

  /// @notice Allows the owner to set a balance cap per `token` for the pool.
  /// @param _token Address of the token to set the balance cap for.
  /// @param _balanceCap New balance cap.
  function _setBalanceCap(address _token, uint256 _balanceCap) internal {
    balanceCap[_token] = _balanceCap;

    emit BalanceCapSet(_token, _balanceCap);
  }

  /// @notice Allows the owner to set a liquidity cap for the pool
  /// @param _liquidityCap New liquidity cap
  function setLiquidityCap(uint256 _liquidityCap) external override onlyOwner {
    _setLiquidityCap(_liquidityCap);
  }

  /// @notice Allows the owner to set a liquidity cap for the pool
  /// @param _liquidityCap New liquidity cap
  function _setLiquidityCap(uint256 _liquidityCap) internal {
    liquidityCap = _liquidityCap;
    emit LiquidityCapSet(_liquidityCap);
  }

  /// @notice Set prize pool ticket.
  /// @param _ticket Address of the ticket to set.
  /// @return True if ticket has been successfully set.
  function setTicket(IControlledToken _ticket) external override onlyOwner returns (bool) {
    require(address(_ticket) != address(0), "PrizePool/ticket-not-zero-address");
    require(address(ticket) == address(0), "PrizePool/ticket-already-set");

    ticket = _ticket;

    emit TicketSet(_ticket);

    return true;
  }

  /// @notice Sets the prize strategy of the prize pool.  Only callable by the owner.
  /// @param _prizeStrategy The new prize strategy
  function setPrizeStrategy(address _prizeStrategy) external override onlyOwner {
    _setPrizeStrategy(_prizeStrategy);
  }

  /// @notice Sets the prize strategy of the prize pool.  Only callable by the owner.
  /// @param _prizeStrategy The new prize strategy
  function _setPrizeStrategy(address _prizeStrategy) internal {
    require(_prizeStrategy != address(0), "PrizePool/prizeStrategy-not-zero");

    prizeStrategy = _prizeStrategy;

    emit PrizeStrategySet(_prizeStrategy);
  }

  /// @dev Gets the current time as represented by the current block
  /// @return The timestamp of the current block
  function _currentTime() internal virtual view returns (uint256) {
    return block.timestamp;
  }

  /// @notice The total of all controlled tokens
  /// @return The current total of all tokens
  function accountedBalance() external override view returns (uint256) {
    return _ticketTotalSupply();
  }

  /// @notice Delegate the votes for a Compound COMP-like token held by the prize pool
  /// @param _compLike The COMP-like token held by the prize pool that should be delegated
  /// @param _to The address to delegate to
  function compLikeDelegate(ICompLike _compLike, address _to) external onlyOwner {
    if (_compLike.balanceOf(address(this)) > 0) {
      _compLike.delegate(_to);
    }
  }

  /// @notice Required for ERC721 safe token transfers from smart contracts.
  /// @param _operator The address that acts on behalf of the owner
  /// @param _from The current owner of the NFT
  /// @param _tokenId The NFT to transfer
  /// @param _data Additional data with no specified format, sent in call to `_to`.
  function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external override returns (bytes4){
    return IERC721Receiver.onERC721Received.selector;
  }

  /// @notice The current total of tickets.
  /// @return Ticket total supply.
  function _ticketTotalSupply() internal view returns (uint256) {
    return ticket.totalSupply();
  }

  /// @dev Checks if `user` can deposit in the Prize Pool based on the current balance cap.
  /// @param _user Address of the user depositing.
  /// @param _amount The amount of tokens to be deposited into the Prize Pool.
  /// @return True if the Prize Pool can receive the specified `amount` of tokens.
  function _canDeposit(address _user, uint256 _amount) internal view returns (bool) {
    IControlledToken _ticket = ticket;
    uint256 _balanceCap = balanceCap[address(_ticket)];

    if (_balanceCap == type(uint256).max) return true;

    return (_ticket.balanceOf(_user) + _amount <= _balanceCap);
  }

  /// @dev Checks if the Prize Pool can receive liquidity based on the current cap
  /// @param _amount The amount of liquidity to be added to the Prize Pool
  /// @return True if the Prize Pool can receive the specified amount of liquidity
  function _canAddLiquidity(uint256 _amount) internal view returns (bool) {
    uint256 _liquidityCap = liquidityCap;
    if(_liquidityCap == type(uint256).max) return true;
    return (_ticketTotalSupply() + _amount <= _liquidityCap);
  }

  /// @dev Checks if a specific token is controlled by the Prize Pool
  /// @param _controlledToken The address of the token to check
  /// @return True if the token is a controlled token, false otherwise
  function _isControlled(IControlledToken _controlledToken) internal view returns (bool) {
    if (ticket == _controlledToken) {
      return true;
    }

    return false;
  }

  /// @dev Checks if a specific token is controlled by the Prize Pool
  /// @param _controlledToken The address of the token to check
  /// @return True if the token is a controlled token, false otherwise
  function isControlled(IControlledToken _controlledToken) external view returns (bool) {
    return _isControlled(_controlledToken);
  }

  /// @notice Determines whether the passed token can be transferred out as an external award.
  /// @dev Different yield sources will hold the deposits as another kind of token: such a Compound's cToken.  The
  /// prize strategy should not be allowed to move those tokens.
  /// @param _externalToken The address of the token to check
  /// @return True if the token may be awarded, false otherwise
  function _canAwardExternal(address _externalToken) internal virtual view returns (bool);

  /// @notice Returns the ERC20 asset token used for deposits.
  /// @return The ERC20 asset token
  function _token() internal virtual view returns (IERC20);

  /// @notice Returns the total balance (in asset tokens).  This includes the deposits and interest.
  /// @return The underlying balance of asset tokens
  function _balance() internal virtual returns (uint256);

  /// @notice Supplies asset tokens to the yield source.
  /// @param mintAmount The amount of asset tokens to be supplied
  function _supply(uint256 mintAmount) internal virtual;

  /// @notice Redeems asset tokens from the yield source.
  /// @param redeemAmount The amount of yield-bearing tokens to be redeemed
  /// @return The actual amount of tokens that were redeemed.
  function _redeem(uint256 redeemAmount) internal virtual returns (uint256);

  /// @dev Function modifier to ensure caller is the prize-strategy
  modifier onlyPrizeStrategy() {
    require(_msgSender() == prizeStrategy, "PrizePool/only-prizeStrategy");
    _;
  }

  /// @dev Function modifier to ensure the deposit amount does not exceed the liquidity cap (if set)
  modifier canAddLiquidity(uint256 _amount) {
    require(_canAddLiquidity(_amount), "PrizePool/exceeds-liquidity-cap");
    _;
  }
}
