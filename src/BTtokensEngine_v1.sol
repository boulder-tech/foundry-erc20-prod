// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { console2 } from "forge-std/Test.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
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

contract BTtokensEngine_v1 is Initializable, UUPSUpgradeable, OwnableUpgradeable, PausableUpgradeable {
    ///////////////////
    //    Errors    ///
    ///////////////////
    error BTtokensEngine__EngineShouldNotBeInitialized();
    error BTtokensEngine__AddressCanNotBeZero();
    error BTtokensEngine__AccountIsBlacklisted();
    error BTtokensEngine__TokenNameAndSymbolAlreadyInUsed();
    error BTtokensEngine__TokenImplementationAlreadyInUse();
    error BTtokensEngine__EnginePaused();
    error BTtokensEngine__EngineNotPaused();
    error BTtokensEngine__TokenNotDeployed();

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
    bool public s_enginePaused = true;
    bytes32[] public s_deployedTokensKeys;
    bytes4[] public s_selectors;
    // Roles are uint64 (0 is reserved for the ADMIN_ROLE)
    uint64 public constant AGENT = 10;
    uint64 public constant PAUSER = 11;

    /// @dev Using `constant` saves gas by computing the function selector at compile time
    ///      instead of during contract execution.
    bytes4 public constant MINT_4_BYTES = bytes4(keccak256("mint(address,uint256)"));
    bytes4 public constant BURN_4_BYTES = bytes4(keccak256("burn(address,uint256)"));
    bytes4 public constant PAUSE_4_BYTES = bytes4(keccak256("pauseToken()"));
    bytes4 public constant UNPAUSE_4_BYTES = bytes4(keccak256("unPauseToken()"));

    //////////////////
    //    Events   ///
    //////////////////

    event TokenCreated(address indexed engine, address indexed tokenProxyAddress, string name, string symbol);
    event Blacklisted(address indexed user);
    event UnBlacklisted(address indexed user);
    event NewTokenImplementationSet(address indexed newTokenImplementation);
    event MinterRoleSet(address indexed tokenProxyAddress, address indexed agent);
    event BurnerRoleSet(address indexed tokenProxyAddress, address indexed agent);
    event PauserRoleSet(address indexed tokenProxyAddress, address indexed pauser);
    event UnPauserRoleSet(address indexed tokenProxyAddress, address indexed pauser);
    event EnginePaused(address indexed engine);
    event EngineUnpaused(address indexed engine);

    ///////////////////
    //   Modifiers  ///
    ///////////////////

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

    modifier nonRepeatedTokenImplementationAddress(address newTokenImplementationAddress) {
        if (newTokenImplementationAddress == s_tokenImplementationAddress) {
            revert BTtokensEngine__TokenImplementationAlreadyInUse();
        }
        _;
    }

    modifier whenNotEnginePaused() {
        if (s_enginePaused) {
            revert BTtokensEngine__EnginePaused();
        }
        _;
    }

    modifier whenEnginePaused() {
        if (!s_enginePaused) {
            revert BTtokensEngine__EngineNotPaused();
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
        nonZeroAddress(initialOwner)
        nonZeroAddress(tokenImplementationAddress)
        nonZeroAddress(accessManagerAddress)
    {
        __Ownable_init(initialOwner);
        __Pausable_init();
        __UUPSUpgradeable_init();
        s_tokenImplementationAddress = tokenImplementationAddress;
        s_accessManagerAddress = accessManagerAddress;
        s_initialized = true;
        s_enginePaused = false; // Set role to pause the engine?
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
        _setBurnerRole(address(newProxyToken), agent);
        // _setPauserRole(address(newProxyToken), address(this));
        // _setUnPauserRole(address(newProxyToken), address(this));

        emit TokenCreated(address(this), address(newProxyToken), tokenName, tokenSymbol);
        return address(newProxyToken);
    }

    /////////   Admin functions   /////////

    /**
     * @notice This function sets a new token implementation address. Once set all tokens deployed by this engine will
     * use the new implementation. We should upgrade the already deployed tokens.
     * @param newTokenImplementationAddress New token implementation address
     */
    function setNewTokenImplementationAddress(address newTokenImplementationAddress)
        external
        onlyOwner
        nonZeroAddress(newTokenImplementationAddress)
        nonRepeatedTokenImplementationAddress(newTokenImplementationAddress)
    {
        s_tokenImplementationAddress = newTokenImplementationAddress;
        emit NewTokenImplementationSet(s_tokenImplementationAddress);
    }

    /////////   Admin functions   /////////
    ///////// Blacklist functions /////////

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

    ///////// Blacklist functions /////////
    /////////   Pause functions   /////////

    /**
     * @notice Function to pause the engine, could be usefull when upgrading.
     */
    function pauseEngine() external onlyOwner whenNotPaused {
        _pauseEngine();
    }

    function unPauseEngine() external onlyOwner whenPaused {
        _unPauseEngine();
    }

    /**
     * @notice Returns the state of the engine.
     */
    function isEnginePaused() external view returns (bool) {
        return s_enginePaused;
    }

    /////////   Pause functions   /////////
    ////////   Getters functions  /////////

    /**
     * @notice This function will be helpfull when upgrading token contracts if token implementation address is updated.
     * @param key Bytes32 key to get the token proxy address
     */
    function getDeployedTokenProxyAddress(bytes32 key) external view returns (address) {
        /// @dev check if the token is deployed, this is a branch
        if (s_deployedTokens[key] == address(0)) {
            revert BTtokensEngine__TokenNotDeployed();
        }
        return s_deployedTokens[key];
    }

    /**
     * @notice This function will be helpfull when upgrading token contracts if token implementation address is updated.
     */
    function getDeployedTokensKeys() external view returns (bytes32[] memory) {
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

    ///////// Blacklist functions /////////

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

    function _isBlacklisted(address _account) internal view virtual returns (bool) {
        return s_blacklist[_account];
    }

    ///////// Blacklist functions /////////
    /////////   Pause functions   /////////

    function _pauseEngine() internal {
        _pause();
        s_enginePaused = true;
        emit EnginePaused(address(this));
    }

    function _unPauseEngine() internal {
        _unpause();
        s_enginePaused = false;
        emit EngineUnpaused(address(this));
    }

    /////////   Pause functions   /////////
    ///////// Set roles functions /////////

    function _setMinterRole(address tokenProxyAddress, address agent) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(s_accessManagerAddress);
        c_manager.grantRole(AGENT, agent, 0);

        _cleanAndPushSelector4Bytes(MINT_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, AGENT);
        emit MinterRoleSet(tokenProxyAddress, agent);
    }

    function _setBurnerRole(address tokenProxyAddress, address agent) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(s_accessManagerAddress);
        c_manager.grantRole(AGENT, agent, 0);

        _cleanAndPushSelector4Bytes(BURN_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, AGENT);
        emit BurnerRoleSet(tokenProxyAddress, agent);
    }

    function _setPauserRole(address tokenProxyAddress, address pauser) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(s_accessManagerAddress);
        c_manager.grantRole(PAUSER, pauser, 0);

        _cleanAndPushSelector4Bytes(PAUSE_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, PAUSER);
        emit PauserRoleSet(tokenProxyAddress, pauser);
    }

    function _setUnPauserRole(address tokenProxyAddress, address pauser) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(s_accessManagerAddress);
        c_manager.grantRole(PAUSER, pauser, 0);

        _cleanAndPushSelector4Bytes(UNPAUSE_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, PAUSER);
        emit UnPauserRoleSet(tokenProxyAddress, pauser);
    }

    function _cleanAndPushSelector4Bytes(bytes4 selector) internal {
        /// @dev clean selectors bytes4 array
        delete s_selectors;
        /// @dev push the bytes4 selector to s_selector
        s_selectors.push(selector);
    }

    ///////// Set roles functions /////////
    /////////  Upgrade functions  /////////

    /**
     * @dev Function that authorizes the upgrade of the contract to a new implementation.     *
     * can authorize an upgrade to a new implementation contract.
     * @param _newImplementation The address of the new implementation contract.
     */
    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner { }

    /**
     * @dev Reserved storage space to allow for layout changes in the future. uint256[50] __gap;
     */
    uint256[50] __gap;
}
