// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { BTtokensEngine_v1 } from "./BTtokensEngine_v1.sol";

/**
 * @title BTtokens_v1, BoulderTech Product Tokens
 * @author BoulderTech Labs
 * @notice This contract implements an ERC20 token with access management,
 *         pausability, and upgradeability through a UUPS proxy.
 *         It enforces blacklist controls and administrative permissions
 *         to ensure secure and regulated usage within the BoulderTech ecosystem.
 *         The token can be paused, minted, and burned under specific restrictions.
 */
contract BTtokens_v1 is
    UUPSUpgradeable,
    ERC20Upgradeable,
    AccessManagedUpgradeable,
    //ERC20PausableUpgradeable//,
    OwnableUpgradeable
{
    ///////////////////
    //    Errors    ///
    ///////////////////
    error BTtokens__AccountIsBlacklisted();
    error BTtokens__AccountIsNotBlacklisted();
    error BTtokens__EngineIsNotPaused();
    error BTtokens__EngineIsPaused();

    ///////////////////
    //     Types    ///
    ///////////////////

    //////////////////////
    // State Variables ///
    //////////////////////

    address public s_engine;
    address public s_manager;
    string public s_name;
    string public s_symbol;
    uint8 public s_decimals;
    bool public s_initialized;
    // bool s_isPaused;
    BTtokensEngine_v1 c_engine;

    //////////////////
    //    Events   ///
    //////////////////

    ///////////////////
    //   Modifiers  ///
    ///////////////////

    modifier notBlacklisted(address account) {
        if (BTtokensEngine_v1(s_engine).isBlacklisted(account)) {
            revert BTtokens__AccountIsBlacklisted();
        }
        _;
    }

    modifier whenEnginePaused() {
        if (!BTtokensEngine_v1(s_engine).isEnginePaused()) {
            revert BTtokens__EngineIsNotPaused();
        }
        _;
    }

    modifier whenNotEnginePaused() {
        if (BTtokensEngine_v1(s_engine).isEnginePaused()) {
            revert BTtokens__EngineIsPaused();
        }
        _;
    }

    ///////////////////
    //   Functions  ///
    ///////////////////

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
        // __ERC20Pausable_init();
        s_engine = engine;
        s_manager = tokenManager;
        s_name = tokenName;
        s_symbol = tokenSymbol;
        s_decimals = tokenDecimals;
        s_initialized = true;
        // s_isPaused = false;
        c_engine = BTtokensEngine_v1(s_engine);
    }

    /////////////////////////
    // External Functions ///
    /////////////////////////

    /**
     * @notice Mint tokens to the desired account.
     * @param _account The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _account, uint256 _amount) public whenNotEnginePaused restricted {
        if (!c_engine.isBlacklisted(_account)) {
            _mint(_account, _amount);
        } else {
            revert BTtokens__AccountIsBlacklisted();
        }
    }

    /**
     * @notice Burn tokens from the desired account.
     * @param _account The address to burn tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _account, uint256 _amount) public restricted {
        if (c_engine.isBlacklisted(_account)) {
            _burn(_account, _amount);
        } else {
            revert BTtokens__AccountIsNotBlacklisted();
        }
    }

    function decimals() public view virtual override returns (uint8) {
        return s_decimals;
    }

    function name() public view virtual override returns (string memory) {
        return s_name;
    }

    function symbol() public view virtual override returns (string memory) {
        return s_symbol;
    }

    function initialized() public view virtual returns (bool) {
        return s_initialized;
    }

    // function isPaused() public view returns (bool) {
    //     return s_isPaused;
    // }

    // /**
    //  * @notice Pause token.
    //  */
    // function pauseToken() public whenNotPaused restricted {
    //     _pause();
    //     s_isPaused = true;
    // }

    // /**
    //  * @notice Unpause token.
    //  */
    // function unPauseToken() public whenPaused restricted {
    //     _unpause();
    //     s_isPaused = false;
    // }

    /**
     * @notice Sets a token allowance for a spender to spend on behalf of the caller.
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
        whenNotEnginePaused
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
        whenNotEnginePaused
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
        whenNotEnginePaused
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /////////////////////////
    // Internal Functions ///
    /////////////////////////

    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable) whenNotEnginePaused {
        super._update(from, to, value);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    uint256[50] __gap;
}
