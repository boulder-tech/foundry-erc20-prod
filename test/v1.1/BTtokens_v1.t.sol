// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";
import { DeployEngine } from "../../script/DeployEngine.s.sol";
import { BTtokensEngine_v1 as EngineV1_0 } from "../../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokensEngine_v1 as EngineV1_1 } from "../../src/BTContracts/v1.1/BTtokensEngine_v1.sol";
import { BTtokens_v1 as TokenV1_0 } from "../../src/BTContracts/v1.0/BTtokens_v1.sol";
import { BTtokens_v1 as TokenV1_1 } from "../../src/BTContracts/v1.1/BTtokens_v1.sol";
import { BTtokensManager } from "../../src/BTContracts/v1.0/BTtokensManager.sol";

/**
 * @title Tests for BTtokens_v1 (token) in v1.1.
 * @notice Engine tests live in BTtokensEngine_v1.t.sol; upgrade flow in UpgradeV1_0_to_V1_1.t.sol.
 *         Here: comportamiento del token v1.1 (mint, burn, transfer, permit, setAccessManager, upgrade, etc.).
 */
contract BTtokensV1_1Test is Test {
    DeployEngine public engineDeployer;
    EngineV1_1 public engineV1_1Impl;
    TokenV1_1 public tokenV1_1Impl;

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public tokenAddress;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");
    address tokenOwner = makeAddr("tokenOwner");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint64 public constant AGENT = 10;

    string constant TOKEN_NAME = "BoulderTestToken";
    string constant TOKEN_SYMBOL = "BTT";
    uint8 constant TOKEN_DECIMALS = 6;

    function setUp() public {
        engineDeployer = new DeployEngine();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin);

        vm.startPrank(initialAdmin);
        BTtokensManager(tokenManagerAddress).grantRole(ADMIN_ROLE, address(engineProxy), 0);
        vm.stopPrank();

        EngineV1_0(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        bytes memory data = abi.encode(
            engineProxy,
            tokenManagerAddress,
            tokenOwner,
            tokenOwner,
            TOKEN_NAME,
            TOKEN_SYMBOL,
            TOKEN_DECIMALS
        );
        tokenAddress = EngineV1_0(engineProxy).createToken(TOKEN_NAME, TOKEN_SYMBOL, data, agent, tokenOwner);

        engineV1_1Impl = new EngineV1_1();
        tokenV1_1Impl = new TokenV1_1();

        vm.startPrank(address(this));
        EngineV1_0(engineProxy).pauseEngine();
        EngineV1_0(engineProxy).upgradeToAndCall(address(engineV1_1Impl), "");
        EngineV1_0(engineProxy).unPauseEngine();
        vm.stopPrank();

        vm.startPrank(address(this));
        EngineV1_1(engineProxy).pauseEngine();
        vm.stopPrank();
        vm.prank(tokenOwner);
        TokenV1_0(tokenAddress).upgradeToAndCall(address(tokenV1_1Impl), "");
        vm.prank(address(this));
        EngineV1_1(engineProxy).unPauseEngine();
    }

    function test_TokenIsV1_1() public {
        assertEq(TokenV1_1(tokenAddress).getVersion(), "1.1");
        assertEq(TokenV1_1(tokenAddress).name(), TOKEN_NAME);
        assertEq(TokenV1_1(tokenAddress).symbol(), TOKEN_SYMBOL);
        assertEq(TokenV1_1(tokenAddress).decimals(), TOKEN_DECIMALS);
        assertEq(TokenV1_1(tokenAddress).s_manager(), tokenManagerAddress);
    }
}
