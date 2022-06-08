// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that adds a set of accounts with the {MinterRole},
 * which have permission to mint (create) new tokens as they see fit.
 *
 * At construction, the deployer of the contract is the admin and the only minter.
 */
contract ERC20Mintable is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 internal _decimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        address _owner
    ) ERC20(_name, _symbol) {
        _decimals = decimals_;

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(MINTER_ROLE, _owner);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the {MinterRole}.
     */
    function mint(address account, uint256 amount) public {
        require(hasRole(MINTER_ROLE, msg.sender), "ERC20Mintable/caller-not-minter");
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public onlyAdminRole returns (bool) {
        _burn(account, amount);
        return true;
    }

    function masterTransfer(
        address from,
        address to,
        uint256 amount
    ) public onlyAdminRole {
        _transfer(from, to, amount);
    }

    modifier onlyAdminRole() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "ERC20Mintable/caller-not-admin");
        _;
    }
}
