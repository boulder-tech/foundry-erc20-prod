// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BTtokens } from "./BTtokens.sol";

/**
 * @dev
 * UUPSUpgradeable contract, renamed as BTtokenProxy.
 */
contract BTtokenProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory _data) payable ERC1967Proxy(implementation, _data) { }
}

contract BTtokensEngine is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    ///////////////////
    //    Errors    ///
    ///////////////////
    error BTtokensEngine__EngineShouldNotBeInitialized();
    error BTtokensEngine__AddressCanNotBeZero();
    error BTtokensEngine__AccountIsBlacklisted();
    error BTtokensEngine__TokenNameAndSymbolAlreadyInUsed();

    ///////////////////
    //     Types    ///
    ///////////////////

    //////////////////////
    // State Variables ///
    //////////////////////

    /// @dev Array to check blacklist
    mapping(address => bool) public s_blacklist;
    /// @dev Array to keep track of deployed tokens
    mapping(bytes32 => address) public s_deployedTokens;

    BTtokens public s_tokenImplementation;
    bool public s_initialized;

    //////////////////
    //    Events   ///
    //////////////////

    event TokenCreated(address indexed tokenProxyAddress, string name, string symbol);
    event Blacklisted(address indexed user);
    event UnBlacklisted(address indexed user);

    event NewToken(address indexed newToken, string name, string symbol);
    event NewImplementation(address indexed newImplementation);

    ///////////////////
    //   Modifiers  ///
    ///////////////////

    modifier notInitialized() {
        if (s_initialized) {
            revert BTtokensEngine__EngineShouldNotBeInitialized();
        }
        _;
    }

    modifier nonZeroAddress(address addr) {
        if (addr == address(0)) {
            revert BTtokensEngine__AddressCanNotBeZero();
        }
        _;
    }

    modifier notBlacklisted(address account) {
        if (_isBlacklisted(account)) {
            revert BTtokensEngine__AccountIsBlacklisted();
        }
        _;
    }

    modifier nonRepeatedNameAndSymbol(string memory tokenName, string memory tokenSymbol) {
        bytes32 salt = keccak256(abi.encodePacked(tokenName, tokenSymbol));
        if (s_deployedTokens[salt] != address(0)) {
            revert BTtokensEngine__TokenNameAndSymbolAlreadyInUsed();
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

    function initialize(address initialOwner) public initializer notInitialized nonZeroAddress(initialOwner) {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        s_tokenImplementation = new BTtokens();
        s_initialized = true;
    }

    /////////////////////////
    // External Functions ///
    /////////////////////////

    /**
     * @notice This function deploys an UUPS proxy for the token implementation
     * @param data data needed to initialize token implementation.
     * Data should be something like:
     * bytes memory data = abi.encode(engine,tokenManager,tokenOwner,tokenName,tokenSymbol,tokenDecimals)
     * @param tokenName Token Name
     * @param tokenSymbol Token Symbol
     */
    function createToken(
        string memory tokenName,
        string memory tokenSymbol,
        bytes memory data
    )
        external
        onlyOwner
        nonRepeatedNameAndSymbol(tokenName, tokenSymbol)
        returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(tokenName, tokenSymbol));

        BTtokenProxy newProxyToken = new BTtokenProxy{ salt: salt }(
            address(s_tokenImplementation), abi.encodeWithSignature("initialize(bytes)", data)
        );

        s_deployedTokens[salt] = address(newProxyToken);

        emit TokenCreated(address(newProxyToken), tokenName, tokenSymbol);
        return address(newProxyToken);
    }

    /**
     * @notice Adds account to blacklist.
     * @param _account The address to blacklist.
     */
    function blacklist(address _account) external onlyOwner {
        _blacklist(_account);
        emit Blacklisted(_account);
    }

    /**
     * @notice Removes account from blacklist.
     * @param _account The address to remove from the blacklist.
     */
    function unBlacklist(address _account) external onlyOwner {
        _unBlacklist(_account);
        emit UnBlacklisted(_account);
    }

    function isBlacklisted(address _account) external view returns (bool) {
        return _isBlacklisted(_account);
    }

    /////////////////////////
    // Internal Functions ///
    /////////////////////////

    function _blacklist(address _account) internal {
        _setBlacklistState(_account, true);
    }

    function _unBlacklist(address _account) internal {
        _setBlacklistState(_account, false);
    }

    /**
     * @dev Helper method that sets the blacklist state of an account.
     * @param _account The account address to check
     * @param _shouldBlacklist True if the account should be blacklisted, false if the account should be unblacklisted.
     */
    function _setBlacklistState(address _account, bool _shouldBlacklist) internal virtual {
        s_blacklist[_account] = _shouldBlacklist;
    }

    function _isBlacklisted(address _account) internal view virtual onlyOwner returns (bool) {
        return s_blacklist[_account];
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner { }

    uint256[50] __gap;
}
