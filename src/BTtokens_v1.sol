// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Blacklistable } from "./Blacklistable.sol";
import { BTtokensEngine_v1 } from "./BTtokensEngine_v1.sol";

contract BTtokens_v1 is
    UUPSUpgradeable,
    ERC20Upgradeable,
    AccessManagedUpgradeable,
    Blacklistable,
    ERC20PausableUpgradeable
{
    // Variables
    address private s_engine;
    address private i_manager;
    string i_name;
    string i_symbol;
    uint8 i_decimals;
    bool s_initialized;
    bool s_isPaused;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(bytes memory data) public initializer {
        (
            address engine,
            address tokenManager,
            address owner,
            string memory tokenName,
            string memory tokenSymbol,
            uint8 tokenDecimals
        ) = abi.decode(data, (address, address, address, string, string, uint8));

        require(!s_initialized, "Token: contract is already initialized");
        require(
            keccak256(abi.encode(tokenName)) != keccak256(abi.encode(""))
                && keccak256(abi.encode(tokenSymbol)) != keccak256(abi.encode("")),
            "invalid argument - empty string"
        );
        require(0 <= tokenDecimals && tokenDecimals <= 18, "decimals between 0 and 18");
        require(engine != address(0), "engine can not be address 0");
        __ERC20_init(tokenName, tokenSymbol);
        __AccessManaged_init(tokenManager);
        __Ownable_init(owner);
        __ERC20Pausable_init();
        s_engine = engine;
        i_manager = tokenManager;
        i_name = tokenName;
        i_symbol = tokenSymbol;
        i_decimals = tokenDecimals;
        s_initialized = true;
        s_isPaused = false;
    }

    function decimals() public view virtual override returns (uint8) {
        return i_decimals;
    }

    function initialized() public view virtual returns (bool) {
        return s_initialized;
    }

    function isPaused() public view returns (bool) {
        return s_isPaused;
    }

    /**
     * @notice Mint tokens to the desired account.
     * @param _account The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _account, uint256 _amount) public whenNotPaused restricted {
        if (!BTtokensEngine_v1(s_engine).isBlacklisted(_account)) {
            _mint(_account, _amount);
            /// ver revert
        }
    }

    /**
     * @notice Burn tokens from the desired account.
     * @param _account The address to burn tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _account, uint256 _amount) public restricted {
        if (_isBlacklisted(_account)) {
            _burn(_account, _amount);
        }
    }

    /**
     * @notice Adds account to blacklist.
     * @param _account The address to blacklist.
     */
    function blacklist(address _account) external restricted {
        _blacklist(_account);
        emit Blacklisted(_account);
    }

    /**
     * @notice Removes account from blacklist.
     * @param _account The address to remove from the blacklist.
     */
    function unBlacklist(address _account) external restricted {
        _unBlacklist(_account);
        emit UnBlacklisted(_account);
    }

    /**
     * @notice Pause token.
     */
    function pauseToken() public whenNotPaused restricted {
        s_isPaused = true;
        _pause();
    }

    /**
     * @notice Unpause token.
     */
    function unPauseToken() public whenPaused restricted {
        s_isPaused = false;
        _unpause();
    }

    /**
     * @inheritdoc Blacklistable
     */
    function _blacklist(address _account) internal override {
        _setBlacklistState(_account, true);
    }

    /**
     * @inheritdoc Blacklistable
     */
    function _unBlacklist(address _account) internal override {
        _setBlacklistState(_account, false);
    }

    /**
     * @dev Helper method that sets the blacklist state of an account.
     * @param _account         The address of the account.
     * @param _shouldBlacklist True if the account should be blacklisted, false if the account should be unblacklisted.
     */
    function _setBlacklistState(address _account, bool _shouldBlacklist) internal virtual {
        _deprecatedBlacklisted[_account] = _shouldBlacklist;
    }

    /**
     * @inheritdoc Blacklistable
     */
    function _isBlacklisted(address _account) internal view virtual override returns (bool) {
        return _deprecatedBlacklisted[_account];
    }

    /**
     * @notice Sets a fiat token allowance for a spender to spend on behalf of the caller.
     * @param spender The spender's address.
     * @param value   The allowance amount.
     * @return True if the operation was successful.
     */
    function approve(
        address spender,
        uint256 value
    )
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(spender)
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /**
     * @notice Transfers tokens from an address to another by spending the caller's allowance.
     * @dev The caller must have some fiat token allowance on the payer's tokens, none of the intervinients addresses
     * should be blacklisted.
     * @param from  Payer's address.
     * @param to    Payee's address.
     * @param value Transfer amount.
     * @return True if the operation was successful.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    )
        public
        virtual
        override
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(from)
        notBlacklisted(to)
        returns (bool)
    {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    /**
     * @notice Transfers tokens from the caller, none of the intervinients addresses should be blacklisted.
     * @param to    Payee's address.
     * @param value Transfer amount.
     * @return True if the operation was successful.
     */
    function transfer(
        address to,
        uint256 value
    )
        public
        virtual
        override(ERC20Upgradeable)
        whenNotPaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function _update(
        address from,
        address to,
        uint256 value
    )
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
        whenNotPaused
    {
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    uint256[50] __gap;
}
