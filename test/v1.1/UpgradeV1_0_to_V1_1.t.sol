// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { DeployEngine } from "../../script/DeployEngine.s.sol";
import { BTtokensEngine_v1 as EngineV1_0 } from "../../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokensEngine_v1 as EngineV1_1 } from "../../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { BTtokens_v1 as TokenV1_0 } from "../../src/BTContracts/v1.0/BTtokens_v1.sol";
import { BTtokens_v1 as TokenV1_1 } from "../../src/BTContracts/v1.1/BTtokens_v1.sol";
import { BTtokensManager } from "../../src/BTContracts/v1.0/BTtokensManager.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title UpgradeV1_0_to_V1_1
 * @notice Tests upgrading engine and token from v1.0 to v1.1.
 *        Flow: deploy v1.0 (DeployEngine) -> init -> create token ->
 *        upgrade engine to v1.1 -> upgrade token to v1.1 -> assert state and changeTokenAccessManager.
 * @dev Storage layout: v1.1 adds s_accessManagerForDeployedTokens and renames
 *      s_accessManagerAddress to s_boulderAccessManagerAddress. If these were
 *      inserted in the middle of state vars, the proxy storage layout may be
 *      incompatible and this test may fail until layout is aligned (e.g. new
 *      vars added from __gap in v1.0).
 */
contract UpgradeV1_0_to_V1_1 is Test {
    DeployEngine public engineDeployer;

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint64 public constant AGENT = 10;

    EngineV1_1 public engineV1_1Implementation;
    TokenV1_1 public tokenV1_1Implementation;

    string constant TOKEN_NAME = "BoulderTestToken";
    string constant TOKEN_SYMBOL = "BTT";
    uint8 constant TOKEN_DECIMALS = 6;

    function setUp() public {
        engineDeployer = new DeployEngine();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin);

        vm.startPrank(initialAdmin);
        BTtokensManager c_manager = BTtokensManager(tokenManagerAddress);
        c_manager.grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();

        EngineV1_0(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        engineV1_1Implementation = new EngineV1_1();
        tokenV1_1Implementation = new TokenV1_1();
    }

    function test_UpgradeV1_0_to_V1_1_StatePreservedAndV1_1Works() public {
        // ---------- 1) Create token with v1.0 ----------
        bytes memory data = abi.encode(
            engineProxy,
            tokenManagerAddress,
            initialAdmin,
            initialAdmin,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        address tokenAddress = EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);
        assertTrue(tokenAddress != address(0));

        TokenV1_0 token = TokenV1_0(tokenAddress);
        assertEq(token.name(), TOKEN_NAME);
        assertEq(token.symbol(), TOKEN_SYMBOL);
        assertEq(token.decimals(), TOKEN_DECIMALS);

        bytes32 salt = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));
        assertEq(EngineV1_0(engineProxy).s_deployedTokens(salt), tokenAddress);

        // ---------- 2) Upgrade engine proxy to v1.1 ----------
        vm.startPrank(address(this));
        EngineV1_0(engineProxy).pauseEngine();
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Implementation), "");
        EngineV1_0(engineProxy).unPauseEngine();
        vm.stopPrank();

        // ---------- 2b) Upgrade token proxy to v1.1 (required for setAccessManager / changeTokenAccessManager) ----------
        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        vm.stopPrank();
        vm.prank(initialAdmin); // token owner
        TokenV1_0(tokenAddress).upgradeToAndCall(address(tokenV1_1Implementation), "");
        vm.startPrank(address(this));
        EngineV1_1(engineProxy).unPauseEngine();
        vm.stopPrank();

        // ---------- 3) Version and engine state (v1.1) ----------
        assertEq(EngineV1_1(engineProxy).getVersion(), "1.1");
        assertTrue(EngineV1_1(engineProxy).s_initialized());
        assertEq(EngineV1_1(engineProxy).s_tokenImplementationAddress(), tokenImplementationAddress);
        assertFalse(EngineV1_1(engineProxy).s_enginePaused());
        assertEq(EngineV1_1(engineProxy).owner(), address(this));

        // ---------- 4) Token is now v1.1 and still usable ----------
        assertEq(EngineV1_1(engineProxy).s_deployedTokens(salt), tokenAddress);
        TokenV1_1 tokenAfter = TokenV1_1(tokenAddress);
        assertEq(tokenAfter.getVersion(), "1.1");
        assertEq(tokenAfter.name(), TOKEN_NAME);
        assertEq(tokenAfter.symbol(), TOKEN_SYMBOL);
        assertEq(tokenAfter.decimals(), TOKEN_DECIMALS);
        assertEq(tokenAfter.s_manager(), tokenManagerAddress);

        // ---------- 5) v1.1: getAccessManagerForDeployedToken not populated until changeTokenAccessManager ----------
        // Token was created under v1.0 so engine never wrote s_accessManagerForDeployedTokens for it.
        address storedManager = EngineV1_1(engineProxy).getAccessManagerForDeployedToken(salt);
        assertEq(storedManager, address(0));
    }

    function test_UpgradeV1_0_to_V1_1_RequiresPaused() public {
        bytes memory data = abi.encode(
            engineProxy,
            tokenManagerAddress,
            initialAdmin,
            initialAdmin,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);

        vm.startPrank(address(this));
        vm.expectRevert(EngineV1_0.BTtokensEngine__EngineNotPaused.selector);
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Implementation), "");
        vm.stopPrank();
    }

    function test_UpgradeV1_0_to_V1_1_OnlyOwner() public {
        bytes memory data = abi.encode(
            engineProxy,
            tokenManagerAddress,
            initialAdmin,
            initialAdmin,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);

        address unauthorized = makeAddr("unauthorized");
        vm.startPrank(address(this));
        EngineV1_0(engineProxy).pauseEngine();
        vm.stopPrank();
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, unauthorized));
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Implementation), "");
    }

    /// @notice Full upgrade (engine + token) then test changeTokenAccessManager (v1.1-only).
    function test_UpgradeV1_0_to_V1_1_ChangeTokenAccessManager() public {
        bytes memory data = abi.encode(
            engineProxy,
            tokenManagerAddress,
            initialAdmin,
            initialAdmin,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        address tokenAddress = EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, initialAdmin);
        bytes32 salt = keccak256(abi.encodePacked(TOKEN_NAME, TOKEN_SYMBOL));

        // Upgrade engine to v1.1
        vm.startPrank(address(this));
        EngineV1_0(engineProxy).pauseEngine();
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Implementation), "");
        EngineV1_0(engineProxy).unPauseEngine();
        vm.stopPrank();

        // Upgrade token to v1.1 (required for setAccessManager used by changeTokenAccessManager)
        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        vm.stopPrank();
        vm.prank(initialAdmin);
        TokenV1_0(tokenAddress).upgradeToAndCall(address(tokenV1_1Implementation), "");
        vm.prank(address(this));
        EngineV1_1(engineProxy).unPauseEngine();

        assertEq(TokenV1_1(tokenAddress).s_manager(), tokenManagerAddress);
        assertEq(EngineV1_1(engineProxy).getAccessManagerForDeployedToken(salt), address(0));

        // Deploy a second access manager and change the token's manager via engine (v1.1)
        BTtokensManager secondManager = new BTtokensManager(initialAdmin);
        vm.prank(initialAdmin);
        secondManager.grantRole(ADMIN_ROLE, address(engineProxy), 0);

        vm.prank(address(this));
        EngineV1_1(engineProxy).changeTokenAccessManager(tokenAddress, address(secondManager));

        assertEq(TokenV1_1(tokenAddress).s_manager(), address(secondManager));
        assertEq(EngineV1_1(engineProxy).getAccessManagerForDeployedToken(salt), address(secondManager));
    }

    /// @notice After upgrading engine to v1.1, set s_tokenImplementationAddress to token v1.1,
    ///         deploy a new token and assert it is v1.1 (and engine records its access manager).
    function test_UpgradeV1_0_to_V1_1_NewTokensUseV1_1Implementation() public {
        // Create first token with v1.0, then upgrade engine to v1.1
        bytes memory data1 = abi.encode(
            engineProxy,
            tokenManagerAddress,
            initialAdmin,
            initialAdmin,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data1, agent, initialAdmin);

        vm.startPrank(address(this));
        EngineV1_0(engineProxy).pauseEngine();
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Implementation), "");
        EngineV1_0(engineProxy).unPauseEngine();
        vm.stopPrank();

        // Set engine's token implementation to v1.1 so new tokens are deployed with v1.1
        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        EngineV1_1(engineProxy).setNewTokenImplementationAddress(address(tokenV1_1Implementation));
        EngineV1_1(engineProxy).unPauseEngine();
        vm.stopPrank();

        assertEq(EngineV1_1(engineProxy).s_tokenImplementationAddress(), address(tokenV1_1Implementation));

        // Deploy a second token (must use different name/symbol)
        string memory name2 = "BoulderTestToken2";
        string memory symbol2 = "BTT2";
        bytes memory data2 = abi.encode(
            engineProxy,
            tokenManagerAddress,
            initialAdmin,
            initialAdmin,
            name2,
            symbol2,
            TOKEN_DECIMALS
        );
        address token2 = EngineV1_1(engineProxy).createToken(name2, symbol2, data2, agent, initialAdmin);
        assertTrue(token2 != address(0));

        // New token is v1.1 from birth
        assertEq(TokenV1_1(token2).getVersion(), "1.1");
        assertEq(TokenV1_1(token2).name(), name2);
        assertEq(TokenV1_1(token2).symbol(), symbol2);
        assertEq(TokenV1_1(token2).s_manager(), tokenManagerAddress);

        // Engine v1.1 records the access manager for newly deployed tokens
        bytes32 salt2 = keccak256(abi.encodePacked(name2, symbol2));
        assertEq(EngineV1_1(engineProxy).getAccessManagerForDeployedToken(salt2), tokenManagerAddress);
    }
}
