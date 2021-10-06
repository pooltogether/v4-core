// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./libraries/TwabLib.sol";
import "./interfaces/ITicket.sol";
import "./ControlledToken.sol";

/**
  * @title  PoolTogether V4 Ticket
  * @author PoolTogether Inc Team
  * @notice The Ticket extends the standard ERC20 and ControlledToken interfaces with time-weighed average balance functionality.
            The TWAB (time-weighed average balance) enables contract-to-contract lookups of a user's average balance
            between timestamps. The timestamp/balance checkpoints are stored in a ring buffer for each user Account.
            Historical searches of a TWAB(s) are limited to the storage of these checkpoints. A user's average balance can
            be delegated to an alternative address. When delegating, the average weighted balance is added to the delegate
            TWAB lookup and removed from the delegaters TWAB lookup.
*/
contract Ticket is ControlledToken, ITicket {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Record of token holders TWABs for each account.
    mapping(address => TwabLib.Account) internal userTwabs;

    /// @notice Record of tickets total supply and ring buff parameters used for observation.
    TwabLib.Account internal totalSupplyTwab;

    /// @notice Mapping of delegates.  Each address can delegate their ticket power to another.
    mapping(address => address) internal delegates;

    /// @notice Each address's balance
    mapping(address => uint256) internal balances;

    /* ============ Constructor ============ */

    /**
     * @notice Constructs Ticket with passed parameters.
     * @param _name ERC20 ticket token name.
     * @param _symbol ERC20 ticket token symbol.
     * @param decimals_ ERC20 ticket token decimals.
     * @param _controller ERC20 ticket controller address (ie: Prize Pool address).
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        address _controller
    ) ControlledToken(_name, _symbol, decimals_, _controller) {}

    /* ============ External Functions ============ */

    /// @inheritdoc ITicket
    function getAccountDetails(address _user)
        external
        view
        override
        returns (TwabLib.AccountDetails memory)
    {
        return userTwabs[_user].details;
    }

    /// @inheritdoc ITicket
    function getTwab(address _user, uint16 _index)
        external
        view
        override
        returns (ObservationLib.Observation memory)
    {
        return userTwabs[_user].twabs[_index];
    }

    /// @inheritdoc ITicket
    function getBalanceAt(address _user, uint256 _target) external view override returns (uint256) {
        TwabLib.Account storage account = userTwabs[_user];

        return
            TwabLib.getBalanceAt(
                account.twabs,
                account.details,
                uint32(_target),
                uint32(block.timestamp)
            );
    }

    /// @inheritdoc ITicket
    function getAverageBalancesBetween(
        address user,
        uint32[] calldata startTimes,
        uint32[] calldata endTimes
    ) external view override returns (uint256[] memory) {
        return _getAverageBalancesBetween(userTwabs[user], startTimes, endTimes);
    }

    /// @inheritdoc ITicket
    function getAverageTotalSuppliesBetween(
        uint32[] calldata startTimes,
        uint32[] calldata endTimes
    ) external view override returns (uint256[] memory) {
        return _getAverageBalancesBetween(totalSupplyTwab, startTimes, endTimes);
    }

    /// @inheritdoc ITicket
    function getAverageBalanceBetween(
        address _user,
        uint256 _startTime,
        uint256 _endTime
    ) external view override returns (uint256) {
        TwabLib.Account storage account = userTwabs[_user];

        return
            TwabLib.getAverageBalanceBetween(
                account.twabs,
                account.details,
                uint32(_startTime),
                uint32(_endTime),
                uint32(block.timestamp)
            );
    }

    /// @inheritdoc ITicket
    function getBalancesAt(address _user, uint32[] calldata _targets)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 length = _targets.length;
        uint256[] memory _balances = new uint256[](length);

        TwabLib.Account storage twabContext = userTwabs[_user];
        TwabLib.AccountDetails memory details = twabContext.details;

        for (uint256 i = 0; i < length; i++) {
            _balances[i] = TwabLib.getBalanceAt(
                twabContext.twabs,
                details,
                _targets[i],
                uint32(block.timestamp)
            );
        }

        return _balances;
    }

    /// @inheritdoc ITicket
    function getTotalSupplyAt(uint32 _target) external view override returns (uint256) {
        return
            TwabLib.getBalanceAt(
                totalSupplyTwab.twabs,
                totalSupplyTwab.details,
                _target,
                uint32(block.timestamp)
            );
    }

    /// @inheritdoc ITicket
    function getTotalSuppliesAt(uint32[] calldata _targets)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256 length = _targets.length;
        uint256[] memory totalSupplies = new uint256[](length);

        TwabLib.AccountDetails memory details = totalSupplyTwab.details;

        for (uint256 i = 0; i < length; i++) {
            totalSupplies[i] = TwabLib.getBalanceAt(
                totalSupplyTwab.twabs,
                details,
                _targets[i],
                uint32(block.timestamp)
            );
        }

        return totalSupplies;
    }

    /// @inheritdoc ITicket
    function delegateOf(address _user) external view override returns (address) {
        return delegates[_user];
    }

    /// @inheritdoc IERC20
    function balanceOf(address _user) public view override returns (uint256) {
        return _balanceOf(_user);
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override returns (uint256) {
        return totalSupplyTwab.details.balance;
    }

    /// @inheritdoc ITicket
    function delegate(address to) external virtual override {
        uint224 balance = uint224(_balanceOf(msg.sender));
        address currentDelegate = delegates[msg.sender];

        require(currentDelegate != to, "Ticket/delegate-already-set");

        if (currentDelegate != address(0)) {
            _decreaseUserTwab(msg.sender, currentDelegate, balance);
        } else {
            _decreaseUserTwab(msg.sender, msg.sender, balance);
        }

        if (to != address(0)) {
            _increaseUserTwab(msg.sender, to, balance);
        } else {
            _increaseUserTwab(msg.sender, msg.sender, balance);
        }

        delegates[msg.sender] = to;

        emit Delegated(msg.sender, to);
    }

    /* ============ Internal Functions ============ */

    /**
    * @notice Returns the ERC20 ticket token balance of a ticket holder.
    * @return uint256 `_user` ticket token balance.
    */
    function _balanceOf(address _user) internal view returns (uint256) {
        return balances[_user];
    }

    /**
     * @notice Retrieves the average balances held by a user for a given time frame.
     * @param _account The user whose balance is checked.
     * @param _startTimes The start time of the time frame.
     * @param _endTimes The end time of the time frame.
     * @return The average balance that the user held during the time frame.
     */
    function _getAverageBalancesBetween(
        TwabLib.Account storage _account,
        uint32[] calldata _startTimes,
        uint32[] calldata _endTimes
    ) internal view returns (uint256[] memory) {
        require(_startTimes.length == _endTimes.length, "Ticket/start-end-times-length-match");

        TwabLib.AccountDetails storage accountDetails = _account.details;
        uint256[] memory averageBalances = new uint256[](_startTimes.length);

        for (uint256 i = 0; i < _startTimes.length; i++) {
            averageBalances[i] = TwabLib.getAverageBalanceBetween(
                _account.twabs,
                accountDetails,
                _startTimes[i],
                _endTimes[i],
                uint32(block.timestamp)
            );
        }

        return averageBalances;
    }

    /**
    * @notice Overridding of the `_transfer` function of the base ERC20 contract.
    * @dev `_sender` cannot be the zero address.
    * @dev `_recipient` cannot be the zero address.
    * @dev `_sender` must have a balance of at least `_amount`.
    * @param _sender Address of the `_sender`that will send `_amount` of tokens.
    * @param _recipient Address of the `_recipient`that will receive `_amount` of tokens.
    * @param _amount Amount of tokens to be transferred from `_sender` to `_recipient`.
    */
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal virtual override {
        require(_sender != address(0), "ERC20: transfer from the zero address");
        require(_recipient != address(0), "ERC20: transfer to the zero address");

        uint224 amount = uint224(_amount);

        _beforeTokenTransfer(_sender, _recipient, _amount);

        if (_sender != _recipient) {
            // standard balance update
            uint256 senderBalance = balances[_sender];
            require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

            unchecked {
                balances[_sender] = senderBalance - amount;
            }

            balances[_recipient] += amount;

            // history update
            address senderDelegate = delegates[_sender];

            if (senderDelegate != address(0)) {
                _decreaseUserTwab(_sender, senderDelegate, _amount);
            } else {
                _decreaseUserTwab(_sender, _sender, _amount);
            }

            // history update
            address recipientDelegate = delegates[_recipient];

            if (recipientDelegate != address(0)) {
                _increaseUserTwab(_recipient, recipientDelegate, amount);
            } else {
                _increaseUserTwab(_recipient, _recipient, amount);
            }
        }

        emit Transfer(_sender, _recipient, _amount);

        _afterTokenTransfer(_sender, _recipient, _amount);
    }

    /**
    * @notice Overridding of the `_mint` function of the base ERC20 contract.
    * @dev `_to` cannot be the zero address.
    * @param _to Address that will be minted `_amount` of tokens.
    * @param _amount Amount of tokens to be minted to `_to`.
    */
    function _mint(address _to, uint256 _amount) internal virtual override {
        require(_to != address(0), "ERC20: mint to the zero address");

        uint224 amount = _amount.toUint224();

        _beforeTokenTransfer(address(0), _to, _amount);

        balances[_to] += amount;

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory _totalSupply,
            bool tsIsNew
        ) = TwabLib.increaseBalance(totalSupplyTwab, amount, uint32(block.timestamp));

        totalSupplyTwab.details = accountDetails;

        if (tsIsNew) {
            emit NewTotalSupplyTwab(_totalSupply);
        }

        address toDelegate = delegates[_to];

        if (toDelegate != address(0)) {
            _increaseUserTwab(_to, toDelegate, amount);
        } else {
            _increaseUserTwab(_to, _to, amount);
        }

        emit Transfer(address(0), _to, _amount);

        _afterTokenTransfer(address(0), _to, _amount);
    }

    /**
    * @notice Overridding of the `_burn` function of the base ERC20 contract.
    * @dev `_from` cannot be the zero address.
    * @dev `_from` must have at least `_amount` of tokens.
    * @param _from Address that will be burned `_amount` of tokens.
    * @param _amount Amount of tokens to be burnt from `_from`.
    */
    function _burn(address _from, uint256 _amount) internal virtual override {
        require(_from != address(0), "ERC20: burn from the zero address");

        uint224 amount = _amount.toUint224();

        _beforeTokenTransfer(_from, address(0), _amount);

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory tsTwab,
            bool tsIsNew
        ) = TwabLib.decreaseBalance(
                totalSupplyTwab,
                amount,
                "Ticket/burn-amount-exceeds-total-supply-twab",
                uint32(block.timestamp)
            );

        totalSupplyTwab.details = accountDetails;

        if (tsIsNew) {
            emit NewTotalSupplyTwab(tsTwab);
        }

        uint256 accountBalance = balances[_from];

        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");

        unchecked {
            balances[_from] = accountBalance - amount;
        }

        address fromDelegate = delegates[_from];

        if (fromDelegate != address(0)) {
            _decreaseUserTwab(_from, fromDelegate, amount);
        } else {
            _decreaseUserTwab(_from, _from, amount);
        }

        emit Transfer(_from, address(0), _amount);

        _afterTokenTransfer(_from, address(0), _amount);
    }

    /**
    * @notice Increase `_user` TWAB balance.
    * @dev If `_user` has not set a delegate address, `_user` TWAB balance will be increased.
    * @dev Otherwise, `_delegate` TWAB balance will be increased.
    * @param _user Address of the user.
    * @param _delegate Address of the delegate.
    * @param _amount Amount of tokens to be added to `_user` TWAB balance.
    */
    function _increaseUserTwab(
        address _user,
        address _delegate,
        uint256 _amount
    ) internal {
        TwabLib.Account storage _account = userTwabs[_delegate];

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory twab,
            bool isNew
        ) = TwabLib.increaseBalance(_account, _amount, uint32(block.timestamp));

        _account.details = accountDetails;

        if (isNew) {
            emit NewUserTwab(_user, _delegate, twab);
        }
    }

    /**
    * @notice Decrease `_user` TWAB balance.
    * @dev If `_user` has not set a delegate address, `_user` TWAB balance will be decreased.
    * @dev Otherwise, `_delegate` TWAB balance will be decreased.
    * @param _user Address of the user.
    * @param _delegate Address of the delegate.
    * @param _amount Amount of tokens to be added to `_user` TWAB balance.
    */
    function _decreaseUserTwab(
        address _user,
        address _delegate,
        uint256 _amount
    ) internal {
        TwabLib.Account storage _account = userTwabs[_delegate];

        (
            TwabLib.AccountDetails memory accountDetails,
            ObservationLib.Observation memory twab,
            bool isNew
        ) = TwabLib.decreaseBalance(
                _account,
                _amount,
                "ERC20: burn amount exceeds balance",
                uint32(block.timestamp)
            );

        _account.details = accountDetails;

        if (isNew) {
            emit NewUserTwab(_user, _delegate, twab);
        }
    }
}
