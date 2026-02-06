// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { BTtokens_v1 } from "./BTtokens_v1.sol";
import { BTtokensManager } from "./BTtokensManager.sol";

/**
 * @dev
 * UUPSUpgradeable contract, renamed as BTtokenProxy.
 */
contract BTtokenProxy is ERC1967Proxy {
    constructor(address implementation, bytes memory _data) payable ERC1967Proxy(implementation, _data) { }
}

contract BTtokensEngine_v1 is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard
{
    ///////////////////
    //    Errors    ///
    ///////////////////
    error BTtokensEngine__EngineShouldNotBeInitialized();
    error BTtokensEngine__AddressCanNotBeZero();
    error BTtokensEngine__AccountIsBlacklisted();
    error BTtokensEngine__AccountIsNotBlacklisted();
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
    /// @dev Array to track access manager for deployed tokens
    mapping(bytes32 => address) public s_accessManagerForDeployedTokens;

    address public s_tokenImplementationAddress;
    address public s_boulderAccessManagerAddress;
    bool public s_initialized;
    bool public s_enginePaused = true;
    bytes32[] public s_deployedTokensKeys;
    bytes4[] public s_selectors;
    /// @dev Roles are uint64 (0 is reserved for the ADMIN_ROLE)
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
    event NewTokenImplementationSet(address indexed engine, address indexed newTokenImplementation);
    event MinterRoleSet(address indexed tokenProxyAddress, address indexed agent);
    event BurnerRoleSet(address indexed tokenProxyAddress, address indexed agent);
    event EnginePaused(address indexed engine);
    event EngineUnpaused(address indexed engine);
    event TokenNameAndSymbolChanged(
        address indexed engine,
        address indexed tokenProxyAddress,
        string name,
        string symbol,
        string newTokenName,
        string newTokenSymbol
    );
    event AccessManagerSet(address indexed engine, address indexed accessManager, address indexed tokenProxyAddress);
    event AccessManagerChanged(
        address indexed engine,
        address indexed tokenProxyAddress,
        address oldAccessManager,
        address indexed newAccessManager
    );

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

    modifier blacklisted(address account) {
        if (!_isBlacklisted(account)) {
            revert BTtokensEngine__AccountIsNotBlacklisted();
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

    modifier nonTokenDeployed(bytes32 key) {
        if (s_deployedTokens[key] == address(0)) {
            revert BTtokensEngine__TokenNotDeployed();
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

    /**
     * @notice Initializes the engine.
     * @param initialOwner The address of the initial owner.
     * @param tokenImplementationAddress The address of the token implementation.
     * @param accessManagerAddress The address of BoulderTech's access manager.
     */
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
        s_boulderAccessManagerAddress = accessManagerAddress;
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
     * bytes memory data = abi.encode(engine,tokenManager,tokenOwner,tokenHolder,tokenName,tokenSymbol,tokenDecimals)
     * @param tokenName Token Name
     * @param tokenSymbol Token Symbol
     */
    function createToken(
        string memory tokenName,
        string memory tokenSymbol,
        bytes memory data,
        address tokenAgent,
        address tokenOwner
    )
        external
        onlyOwner
        nonRepeatedNameAndSymbol(tokenName, tokenSymbol)
        whenNotEnginePaused
        nonReentrant
        returns (address)
    {
        bytes32 salt = keccak256(abi.encodePacked(tokenName, tokenSymbol));

        BTtokenProxy newProxyToken = new BTtokenProxy{ salt: salt }(
            address(s_tokenImplementationAddress), abi.encodeWithSignature("initialize(bytes)", data)
        );

        s_deployedTokens[salt] = address(newProxyToken);
        s_deployedTokensKeys.push(salt);

        address tokenManager = BTtokens_v1(address(newProxyToken)).s_manager();

        s_accessManagerForDeployedTokens[salt] = tokenManager;

        /**
         * @notice If the token manager is different from the engine's access manager, we need to update the engine's
         * access manager.
         * @param tokenManager The address of the token manager.
         * @param tokenProxyAddress The address of the token proxy.
         */
        if (tokenManager != s_boulderAccessManagerAddress) {
            emit AccessManagerSet(address(this), tokenManager, address(newProxyToken));
        }

        _setMinterRole(address(newProxyToken), tokenAgent, tokenManager);
        _setMinterRole(address(newProxyToken), tokenOwner, tokenManager);
        _setBurnerRole(address(newProxyToken), tokenAgent, tokenManager);
        _setBurnerRole(address(newProxyToken), tokenOwner, tokenManager);

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
        whenEnginePaused
        nonZeroAddress(newTokenImplementationAddress)
        nonRepeatedTokenImplementationAddress(newTokenImplementationAddress)
    {
        s_tokenImplementationAddress = newTokenImplementationAddress;
        emit NewTokenImplementationSet(address(this), s_tokenImplementationAddress);
    }

    function changeTokenNameAndSymbol(
        string memory tokenName,
        string memory tokenSymbol,
        string memory newTokenName,
        string memory newTokenSymbol
    )
        external
        onlyOwner
        nonRepeatedNameAndSymbol(newTokenName, newTokenSymbol)
    {
        bytes32 key = keccak256(abi.encodePacked(tokenName, tokenSymbol));
        if (s_deployedTokens[key] == address(0)) {
            revert BTtokensEngine__TokenNotDeployed();
        }
        address tokenAddress = s_deployedTokens[key];
        address tokenManager = s_accessManagerForDeployedTokens[key];
        _removeToken(key);

        bytes32 newKey = keccak256(abi.encodePacked(newTokenName, newTokenSymbol));
        s_deployedTokens[newKey] = tokenAddress;
        s_accessManagerForDeployedTokens[newKey] = tokenManager;
        s_deployedTokensKeys.push(newKey);

        BTtokens_v1 c_token = BTtokens_v1(s_deployedTokens[newKey]);

        c_token.setNameAndSymbol(newTokenName, newTokenSymbol);

        emit TokenNameAndSymbolChanged(
            address(this), tokenAddress, tokenName, tokenSymbol, newTokenName, newTokenSymbol
        );
    }

    /**
     * @notice Changes the access manager for a deployed token.
     * @dev Only the engine owner can call this. Updates the token's access manager via setAccessManager
     *      and keeps the engine's s_accessManagerForDeployedTokens in sync. The new manager starts with
     *      no role assignments; use assignMinterRole/assignBurnerRole after this to configure agents.
     * @param tokenProxyAddress The address of the token proxy.
     * @param newAccessManager The address of the new access manager.
     */
    function changeTokenAccessManager(address tokenProxyAddress, address newAccessManager)
        external
        onlyOwner
        nonZeroAddress(tokenProxyAddress)
        nonZeroAddress(newAccessManager)
    {
        BTtokens_v1 c_token = BTtokens_v1(tokenProxyAddress);
        bytes32 key = keccak256(abi.encodePacked(c_token.name(), c_token.symbol()));
        if (s_deployedTokens[key] != tokenProxyAddress) {
            revert BTtokensEngine__TokenNotDeployed();
        }

        address oldAccessManager = c_token.s_manager();
        c_token.setAccessManager(newAccessManager);
        s_accessManagerForDeployedTokens[key] = newAccessManager;

        emit AccessManagerChanged(address(this), tokenProxyAddress, oldAccessManager, newAccessManager);
    }

    /////////   Admin functions   /////////
    ///////// Blacklist functions /////////

    /**
     * @notice Adds account to blacklist.
     * @param _account The address to blacklist.
     */
    function blacklist(address _account) external onlyOwner notBlacklisted(_account) {
        _blacklist(_account);
    }

    /**
     * @notice Adds multiple accounts to blacklist.
     * @param _accounts The addresses to blacklist.
     */
    function batchBlacklist(address[] calldata _accounts) external onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _blacklist(_accounts[i]);
        }
    }

    /**
     * @notice Removes account from blacklist.
     * @param _account The address to remove from the blacklist.
     */
    function unBlacklist(address _account) external onlyOwner blacklisted(_account) {
        _unBlacklist(_account);
    }

    /**
     * @notice Removes multiple accounts from blacklist.
     * @param _accounts The addresses to remove from the blacklist.
     */
    function batchUnblacklist(address[] calldata _accounts) external onlyOwner {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _unBlacklist(_accounts[i]);
        }
    }

    function isBlacklisted(address _account) external view returns (bool) {
        return _isBlacklisted(_account);
    }

    ///////// Blacklist functions /////////
    ///////// Assign role functions ///////
    /**
     * @notice Assigns the minter role to an agent.
     * @param tokenProxyAddress The address of the token proxy.
     * @param agent The address of the agent.
     */
    function assignMinterRole(address tokenProxyAddress, address agent) external onlyOwner {
        address managerAddress = _getManagerAddressForDeployedToken(tokenProxyAddress);
        _setMinterRole(tokenProxyAddress, agent, managerAddress);
    }

    /**
     * @notice Assigns the burner role to an agent.
     * @param tokenProxyAddress The address of the token proxy.
     * @param agent The address of the agent.
     */
    function assignBurnerRole(address tokenProxyAddress, address agent) external onlyOwner {
        address managerAddress = _getManagerAddressForDeployedToken(tokenProxyAddress);
        _setBurnerRole(tokenProxyAddress, agent, managerAddress);
    }

    ///////// Assign role functions ///////
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
    function getDeployedTokenProxyAddress(bytes32 key) external view nonTokenDeployed(key) returns (address) {
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
    function getVersion() external pure virtual returns (string memory) {
        return "1.1";
    }

    /**
     * @notice Returns the access manager for a deployed token. Bear in mind that the access manager for a deployed
     * BoulderTech product token can be obtained from the token contract.
     * @param key Bytes32 key to get the token proxy address
     */
    function getAccessManagerForDeployedToken(bytes32 key) external view nonTokenDeployed(key) returns (address) {
        return s_accessManagerForDeployedTokens[key];
    }

    /////////////////////////
    // Internal Functions ///
    /////////////////////////

    ///////// Blacklist functions /////////

    function _blacklist(address _account) internal {
        _setBlacklistState(_account, true);
        emit Blacklisted(_account);
    }

    function _unBlacklist(address _account) internal {
        _setBlacklistState(_account, false);
        emit UnBlacklisted(_account);
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

    function _setMinterRole(address tokenProxyAddress, address agent, address managerAddress) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(managerAddress);
        c_manager.grantRole(AGENT, agent, 0);

        _cleanAndPushSelector4Bytes(MINT_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, AGENT);
        emit MinterRoleSet(tokenProxyAddress, agent);
    }

    function _setBurnerRole(address tokenProxyAddress, address agent, address managerAddress) internal {
        // Grant the agent role with no execution delay
        BTtokensManager c_manager = BTtokensManager(managerAddress);
        c_manager.grantRole(AGENT, agent, 0);

        _cleanAndPushSelector4Bytes(BURN_4_BYTES);

        c_manager.setTargetFunctionRole(tokenProxyAddress, s_selectors, AGENT);
        emit BurnerRoleSet(tokenProxyAddress, agent);
    }

    function _cleanAndPushSelector4Bytes(bytes4 selector) internal {
        /// @dev clean selectors bytes4 array
        delete s_selectors;
        /// @dev push the bytes4 selector to s_selector
        s_selectors.push(selector);
    }

    ///////// Set roles functions /////////
    /////////   Admin functions   /////////

    function _getManagerAddressForDeployedToken(address tokenProxyAddress) internal view returns (address) {
        BTtokens_v1 c_token = BTtokens_v1(tokenProxyAddress);
        return c_token.s_manager();
    }

    function _removeToken(bytes32 salt) internal {
        /// @dev remove salt from mapping
        delete s_deployedTokens[salt];
        delete s_accessManagerForDeployedTokens[salt];

        /// @dev swap-and-pop
        uint256 len = s_deployedTokensKeys.length;
        for (uint256 i = 0; i < len; i++) {
            if (s_deployedTokensKeys[i] == salt) {
                s_deployedTokensKeys[i] = s_deployedTokensKeys[len - 1];
                s_deployedTokensKeys.pop();
                break;
            }
        }
    }

    /////////   Admin functions   /////////
    /////////  Upgrade functions  /////////

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
