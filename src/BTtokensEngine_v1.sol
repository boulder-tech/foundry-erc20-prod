// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/Test.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BTtokens_v1 } from "./BTtokens_v1.sol";
import { BTtokensManager } from "./BTtokensManager.sol";

/**
 * @dev
 * UUPSUpgradeable contract, renamed as BTtokenProxy.
 */
contract BTtokenProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory _data) payable ERC1967Proxy(implementation, _data) { }
}

contract BTtokensEngine_v1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
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

    address public s_tokenImplementationAddress;
    address public s_accessManagerAddress;
    bool public s_initialized;
    bytes32[] public s_deployedTokensKeys;
    bytes4[] public s_selectors;
    uint64 public constant AGENT = 10; // Roles are uint64 (0 is reserved for the ADMIN_ROLE)
    bytes4 public constant MINT_4_BYTES = bytes4(keccak256("mint(address,uint256)"));

    //////////////////
    //    Events   ///
    //////////////////

    event TokenCreated(address indexed tokenProxyAddress, string name, string symbol);
    event Blacklisted(address indexed user);
    event UnBlacklisted(address indexed user);
    event NewTokenImplementationSet(address indexed newTokenImplementation);

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

    function initialize(
        address initialOwner,
        address tokenImplementationAddress,
        address accessManagerAddress
    )
        public
        initializer
        notInitialized
        nonZeroAddress(initialOwner)
        nonZeroAddress(tokenImplementationAddress)
        nonZeroAddress(accessManagerAddress)
    {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        s_tokenImplementationAddress = tokenImplementationAddress;
        s_accessManagerAddress = accessManagerAddress;
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
        bytes memory data,
        address agent
    )
        external
        onlyOwner
        nonRepeatedNameAndSymbol(tokenName, tokenSymbol)
        returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(tokenName, tokenSymbol));

        BTtokenProxy newProxyToken = new BTtokenProxy{ salt: salt }(
            address(s_tokenImplementationAddress), abi.encodeWithSignature("initialize(bytes)", data)
        );

        s_deployedTokens[salt] = address(newProxyToken);
        s_deployedTokensKeys.push(salt);

        _setMinterRole(address(newProxyToken), agent);

        console2.log("TokenCreated: ", address(newProxyToken), tokenName, tokenSymbol);

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

    /**
     * @notice This function sets a new token implementation address. Once set all tokens deployed by this engine will
     * use the new implementation. We should upgrade the already deployed tokens.
     * @param newTokenImplementationAddress New token implementation address
     */
    function setNewTokenImplementationAddress(address newTokenImplementationAddress)
        external
        onlyOwner
        nonZeroAddress(newTokenImplementationAddress)
    {
        require(newTokenImplementationAddress != s_tokenImplementationAddress, "Already using this implementation");

        s_tokenImplementationAddress = newTokenImplementationAddress;
        emit NewTokenImplementationSet(s_tokenImplementationAddress);
    }

    /**
     * @notice This function will be helpfull when upgrading token contracts if token implementation address is updated.
     * @param key Bytes32 key to get the token proxy address
     */
    function getDeployedTokenProxyAddress(bytes32 key) external view returns (address) {
        return s_deployedTokens[key];
    }

    /**
     * @notice This function will be helpfull when upgrading token contracts if token implementation address is updated.
     */
    function getDeployedTokenKeys() external view returns (bytes32[] memory) {
        return s_deployedTokensKeys;
    }

    /**
     * @notice Returns BTtokensEngine version
     *
     */
    function getVersion() external pure virtual returns (uint16) {
        return 1;
    }

    /////////////////////////
    // Internal Functions ///
    /////////////////////////

    /// Blacklist functions

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

    /// Set roles functions

    function _setMinterRole(address tokenProxyAddress, address agent) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(s_accessManagerAddress);
        c_manager.grantRole(AGENT, agent, 0);

        /// @dev clean selectors bytes4 array
        delete s_selectors;
        /// @dev push the bytes4 selector to s_selector
        s_selectors.push(MINT_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, AGENT);
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner { }

    uint256[50] __gap;
}
