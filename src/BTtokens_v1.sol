// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { AccessManagedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
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
    OwnableUpgradeable,
    ERC20PermitUpgradeable
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
    BTtokensEngine_v1 c_engine;

    //////////////////
    //    Events   ///
    //////////////////
    event TokensMinted(address indexed token, address indexed account, uint256 amount);
    event TokensBurned(address indexed token, address indexed account, uint256 amount);
    event TokensApproved(address indexed token, address indexed owner, address indexed spender, uint256 amount);
    event TransferFrom(
        address indexed token, address indexed spender, address from, address indexed to, uint256 amount
    );
    event TokenTransfer(address indexed token, address indexed from, address indexed to, uint256 amount);
    event PermitAndTransfer(
        address token,
        address indexed sender,
        address indexed owner,
        address indexed to,
        uint256 value,
        uint256 deadline
    );

    ///////////////////
    //   Modifiers  ///
    ///////////////////

    modifier blacklisted(address account) {
        if (!BTtokensEngine_v1(s_engine).isBlacklisted(account)) {
            revert BTtokens__AccountIsNotBlacklisted();
        }
        _;
    }

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
            address tokenEngine,
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
        require(0 < tokenDecimals && tokenDecimals <= 18, "decimals between 0 and 18");
        require(tokenEngine != address(0), "engine can not be address 0");
        require(tokenManager != address(0), "token manager can not be address 0");
        __ERC20_init(tokenName, tokenSymbol);
        __ERC20Permit_init(tokenName);
        __AccessManaged_init(tokenManager);
        __Ownable_init(owner);
        s_engine = tokenEngine;
        s_manager = tokenManager;
        s_name = tokenName;
        s_symbol = tokenSymbol;
        s_decimals = tokenDecimals;
        s_initialized = true;
        c_engine = BTtokensEngine_v1(s_engine);
    }

    /////////////////////////
    // External Functions ///
    /////////////////////////

    /////////   Supply functions   /////////

    /**
     * @notice Mint tokens to the desired account.
     * @param _account The address to mint tokens to.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _account, uint256 _amount) public whenNotEnginePaused notBlacklisted(_account) restricted {
        _mint(_account, _amount);
        emit TokensMinted(address(this), _account, _amount);
    }

    /**
     * @notice Burn tokens from the desired account.
     * @param _account The address to burn tokens from.
     * @param _amount The amount of tokens to burn.
     */
    function burn(address _account, uint256 _amount) public blacklisted(_account) restricted {
        _burn(_account, _amount);
        emit TokensBurned(address(this), _account, _amount);
    }

    function permitAndTransfer(
        address owner,
        address to,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        whenNotEnginePaused
        notBlacklisted(owner)
        notBlacklisted(to)
        notBlacklisted(msg.sender)
    {
        // Use the permit signature to approve the allowance for msg.sender
        permit(owner, msg.sender, value, deadline, v, r, s);

        // Perform the transfer using the newly approved allowance
        _spendAllowance(owner, msg.sender, value);
        _transfer(owner, to, value);

        // Emit the PermitAndTransfer event for tracking
        emit PermitAndTransfer(address(this), msg.sender, owner, to, value, deadline);
        // Emit the custom TransferFrom event for tracking
        emit TransferFrom(address(this), msg.sender, owner, to, value);
    }

    /////////   Supply functions   /////////
    ////////   Getters functions   /////////

    function decimals() public view virtual override returns (uint8) {
        return s_decimals;
    }

    function name() public view virtual override returns (string memory) {
        return s_name;
    }

    function symbol() public view virtual override returns (string memory) {
        return s_symbol;
    }

    function manager() public view virtual returns (address) {
        return s_manager;
    }

    function engine() public view virtual returns (address) {
        return s_engine;
    }

    function initialized() public view virtual returns (bool) {
        return s_initialized;
    }

    function getVersion() external pure virtual returns (uint16) {
        return 1;
    }

    ////////   Getters functions   /////////
    ////////  Transfers functions  /////////

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
        emit TokensApproved(address(this), owner, spender, value);
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
        emit TransferFrom(address(this), address(msg.sender), from, to, value);
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
        emit TokenTransfer(address(this), owner, to, value);
        return true;
    }

    /////////////////////////
    // Internal Functions ///
    /////////////////////////

    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable) {
        super._update(from, to, value);
    }

    /**
     * @dev Function that authorizes the upgrade of the contract to a new implementation.     *
     * can authorize an upgrade to a new implementation contract. Should the engine be paused to upgrade?
     * @param _newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner whenEnginePaused { }

    /**
     * @dev Reserved storage space to allow for layout changes in the future. uint256[50] __gap;
     */
    uint256[50] __gap;
}
