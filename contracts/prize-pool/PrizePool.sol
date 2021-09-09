// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";

import "../external/compound/ICompLike.sol";
import "../interfaces/IPrizePool.sol";

/// @title Escrows assets and deposits them into a yield source.  Exposes interest to Prize Strategy.
///       Users deposit and withdraw from this contract to participate in Prize Pool.
/// @notice Accounting is managed using Controlled Tokens, whose mint and burn functions can only be called by this contract.
/// @dev Must be inherited to provide specific yield-bearing asset control, such as Compound cTokens
abstract contract PrizePool is IPrizePool, OwnableUpgradeable, ReentrancyGuardUpgradeable, IERC721ReceiverUpgradeable {
  using SafeCastUpgradeable for uint256;
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using SafeERC20Upgradeable for IERC721Upgradeable;
  using ERC165CheckerUpgradeable for address;

  /// @dev Emitted when an instance is initialized
  event Initialized(
    address reserveRegistry
  );

  /// @dev Event emitted when controlled token is added
  event ControlledTokenAdded(
    IControlledToken indexed token
  );

  event AwardCaptured(
    uint256 amount
  );

  /// @dev Event emitted when assets are deposited
  event Deposited(
    address indexed operator,
    address indexed to,
    IControlledToken indexed token,
    uint256 amount
  );

  /// @dev Event emitted when interest is awarded to a winner
  event Awarded(
    address indexed winner,
    IControlledToken indexed token,
    uint256 amount
  );

  /// @dev Event emitted when external ERC20s are awarded to a winner
  event AwardedExternalERC20(
    address indexed winner,
    address indexed token,
    uint256 amount
  );

  /// @dev Event emitted when external ERC20s are transferred out
  event TransferredExternalERC20(
    address indexed to,
    address indexed token,
    uint256 amount
  );

  /// @dev Event emitted when external ERC721s are awarded to a winner
  event AwardedExternalERC721(
    address indexed winner,
    address indexed token,
    uint256[] tokenIds
  );

  /// @dev Event emitted when assets are withdrawn instantly
  event Withdrawal(
    address indexed operator,
    address indexed from,
    IControlledToken indexed token,
    uint256 amount,
    uint256 redeemed
  );

  /// @dev Event emitted when the Liquidity Cap is set
  event LiquidityCapSet(
    uint256 liquidityCap
  );

  /// @dev Event emitted when the Prize Strategy is set
  event PrizeStrategySet(
    address indexed prizeStrategy
  );

  /// @dev Emitted when there was an error thrown awarding an External ERC721
  event ErrorAwardingExternalERC721(bytes error);

  /// @notice Semver Version
  string constant public VERSION = "3.4.0";

  /// @dev An array of all the controlled tokens
  IControlledToken[] internal _tokens;

  /// @dev The Prize Strategy that this Prize Pool is bound to.
  address public prizeStrategy;

  /// @dev The total amount of funds that the prize pool can hold.
  uint256 public liquidityCap;

  /// @dev the The awardable balance
  uint256 internal _currentAwardBalance;

  /// @notice Initializes the Prize Pool
  /// @param _controlledTokens Array of ControlledTokens that are controlled by this Prize Pool.
  function initialize (
    IControlledToken[] memory _controlledTokens
  )
    public
    initializer
  {
    uint256 controlledTokensLength = _controlledTokens.length;
    _tokens = new IControlledToken[](controlledTokensLength);

    for (uint256 i = 0; i < controlledTokensLength; i++) {
      IControlledToken controlledToken = _controlledTokens[i];
      _addControlledToken(controlledToken, i);
    }

    __Ownable_init();
    __ReentrancyGuard_init();

    // NOTE: Updated from _setLiquidityCap(uint256(-1));
    uint256 liquidityCapMask = type(uint256).max;
    _setLiquidityCap(liquidityCapMask);
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

  /// @dev Returns the address of a token in the _tokens array.
  /// @return Address of token
  function tokenAtIndex(uint256 tokenIndex) external override view returns (IControlledToken) {
    IControlledToken[] memory __tokens = _tokens;
    require(tokenIndex < __tokens.length, "PrizePool/invalid-token-index");
    return __tokens[tokenIndex];
  }

  /// @dev Checks with the Prize Pool if a specific token type may be awarded as an external prize
  /// @param _externalToken The address of the token to check
  /// @return True if the token may be awarded, false otherwise
  function canAwardExternal(address _externalToken) external view returns (bool) {
    return _canAwardExternal(_externalToken);
  }

  /// @notice Deposit assets into the Prize Pool in exchange for tokens
  /// @param to The address receiving the newly minted tokens
  /// @param amount The amount of assets to deposit
  /// @param controlledToken The address of the type of token the user is minting
  function depositTo(
    address to,
    uint256 amount,
    IControlledToken controlledToken
  )
    external override
    nonReentrant
    onlyControlledToken(controlledToken)
    canAddLiquidity(amount)
  {
    address operator = _msgSender();

    _mint(to, amount, controlledToken);

    _token().safeTransferFrom(operator, address(this), amount);
    _supply(amount);

    emit Deposited(operator, to, controlledToken, amount);
  }

  /// @notice Withdraw assets from the Prize Pool instantly.  A fairness fee may be charged for an early exit.
  /// @param from The address to redeem tokens from.
  /// @param amount The amount of tokens to redeem for assets.
  /// @param controlledToken The address of the token to redeem (i.e. ticket or sponsorship)
  /// @return The actual exit fee paid
  function withdrawFrom(
    address from,
    uint256 amount,
    IControlledToken controlledToken
  )
    external override
    nonReentrant
    onlyControlledToken(controlledToken)
    returns (uint256)
  {
    // burn the tickets
    controlledToken.controllerBurnFrom(_msgSender(), from, amount);

    // redeem the tickets
    uint256 redeemed = _redeem(amount);

    _token().safeTransfer(from, redeemed);

    emit Withdrawal(_msgSender(), from, controlledToken, amount, redeemed);

    return redeemed;
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
    uint256 tokenTotalSupply = _tokenTotalSupply();

    // it's possible for the balance to be slightly less due to rounding errors in the underlying yield source
    uint256 currentBalance = _balance();
    uint256 totalInterest = (currentBalance > tokenTotalSupply) ? currentBalance - tokenTotalSupply : 0;
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
  /// @param _controlledToken The address of the asset token being awarded
  function award(
    address _to,
    uint256 _amount,
    IControlledToken _controlledToken
  )
    external override
    onlyPrizeStrategy
    onlyControlledToken(_controlledToken)
  {
    if (_amount == 0) {
      return;
    }

    require(_amount <= _currentAwardBalance, "PrizePool/award-exceeds-avail");
    _currentAwardBalance = _currentAwardBalance - _amount;

    _mint(_to, _amount, _controlledToken);

    emit Awarded(_to, _controlledToken, _amount);
  }

  /// @notice Called by the Prize-Strategy to transfer out external ERC20 tokens
  /// @dev Used to transfer out tokens held by the Prize Pool.  Could be liquidated, or anything.
  /// @param _to The address of the winner that receives the award
  /// @param _amount The amount of external assets to be awarded
  /// @param _externalToken The address of the external asset token being awarded
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
  /// @param _to The address of the winner that receives the award
  /// @param _amount The amount of external assets to be awarded
  /// @param _externalToken The address of the external asset token being awarded
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

    IERC20Upgradeable(_externalToken).safeTransfer(_to, _amount);

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
      try IERC721Upgradeable(externalToken).safeTransferFrom(address(this), to, tokenIds[i]){

      }
      catch(bytes memory error){
        emit ErrorAwardingExternalERC721(error);
      }

    }

    emit AwardedExternalERC721(to, externalToken, tokenIds);
  }

  /// @notice Allows the Governor to set a cap on the amount of liquidity that he pool can hold
  /// @param _liquidityCap The new liquidity cap for the prize pool
  function setLiquidityCap(uint256 _liquidityCap) external override onlyOwner {
    _setLiquidityCap(_liquidityCap);
  }

  function _setLiquidityCap(uint256 _liquidityCap) internal {
    liquidityCap = _liquidityCap;
    emit LiquidityCapSet(_liquidityCap);
  }

  /// @notice Adds a new controlled token
  /// @param _controlledToken The controlled token to add.
  /// @param _index The index to add the controlledToken
  function _addControlledToken(IControlledToken _controlledToken, uint256 _index) internal {
    require(address(_controlledToken) != address(0), "PrizePool/controlledToken-not-zero-address");

    _tokens[_index] = _controlledToken;

    emit ControlledTokenAdded(_controlledToken);
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

  /// @notice An array of the Tokens controlled by the Prize Pool (ie. Tickets, Sponsorship)
  /// @return An array of controlled token addresses
  function tokens() external override view returns (IControlledToken[] memory) {
    return _tokens;
  }

  /// @dev Gets the current time as represented by the current block
  /// @return The timestamp of the current block
  function _currentTime() internal virtual view returns (uint256) {
    return block.timestamp;
  }

  /// @notice The total of all controlled tokens
  /// @return The current total of all tokens
  function accountedBalance() external override view returns (uint256) {
    return _tokenTotalSupply();
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
    return IERC721ReceiverUpgradeable.onERC721Received.selector;
  }

  /// @notice The total of all controlled tokens
  /// @return The current total of all tokens
  function _tokenTotalSupply() internal view returns (uint256) {
    uint256 total;
    IControlledToken[] memory tokens = _tokens; // SLOAD
    uint256 tokensLength = tokens.length;

    for(uint256 i = 0; i < tokensLength; i++){
      total = total + IERC20Upgradeable(tokens[i]).totalSupply();
    }

    return total;
  }

  /// @dev Checks if the Prize Pool can receive liquidity based on the current cap
  /// @param _amount The amount of liquidity to be added to the Prize Pool
  /// @return True if the Prize Pool can receive the specified amount of liquidity
  function _canAddLiquidity(uint256 _amount) internal view returns (bool) {
    uint256 _liquidityCap = liquidityCap;
    if(_liquidityCap == type(uint256).max) return true;
    return (_tokenTotalSupply() + _amount <= _liquidityCap);
  }

  /// @dev Checks if a specific token is controlled by the Prize Pool
  /// @param controlledToken The address of the token to check
  /// @return True if the token is a controlled token, false otherwise
  function _isControlled(IControlledToken controlledToken) internal view returns (bool) {
    IControlledToken[] memory tokens = _tokens; // SLOAD
    uint256 tokensLength = tokens.length;

    for(uint256 i = 0; i < tokensLength; i++) {
      if(tokens[i] == controlledToken) return true;
    }
    return false;
  }

  /// @dev Checks if a specific token is controlled by the Prize Pool
  /// @param controlledToken The address of the token to check
  /// @return True if the token is a controlled token, false otherwise
  function isControlled(IControlledToken controlledToken) external view returns (bool) {
    return _isControlled(controlledToken);
  }

  /// @notice Determines whether the passed token can be transferred out as an external award.
  /// @dev Different yield sources will hold the deposits as another kind of token: such a Compound's cToken.  The
  /// prize strategy should not be allowed to move those tokens.
  /// @param _externalToken The address of the token to check
  /// @return True if the token may be awarded, false otherwise
  function _canAwardExternal(address _externalToken) internal virtual view returns (bool);

  /// @notice Returns the ERC20 asset token used for deposits.
  /// @return The ERC20 asset token
  function _token() internal virtual view returns (IERC20Upgradeable);

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

  /// @dev Function modifier to ensure usage of tokens controlled by the Prize Pool
  /// @param controlledToken The address of the token to check
  modifier onlyControlledToken(IControlledToken controlledToken) {
    require(_isControlled(controlledToken), "PrizePool/unknown-token");
    _;
  }

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
