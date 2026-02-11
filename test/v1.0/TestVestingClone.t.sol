// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { BTvestingCliffWallet } from "../../src/BTvestingCliffWallet.sol";
import { BTvestingCliffWalletFactory, Ownable } from "../../src/BTvestingCliffWalletFactory.sol";
import { BTtokensEngine_v1 } from "../../src/BTContracts/v1.0/BTtokensEngine_v1.sol";
import { BTtokens_v1 } from "../../src/BTContracts/v1.0/BTtokens_v1.sol";
import { BTtokensManager } from "../../src/BTContracts/v1.0/BTtokensManager.sol";
import { DeployEngine } from "../../script/DeployEngine.s.sol";

interface IVestingWalletClone {
    function initialize(address, uint64, uint64, uint64) external;
    function releasable(address) external view returns (uint256);
    function release(address token) external;
}

contract TestBTvestingCliff is Test {
    DeployEngine public engineDeployer;
    BTtokens_v1 token;

    BTvestingCliffWalletFactory factory;
    BTvestingCliffWallet vestingImplementation;

    address public engineProxy;
    address public tokenImplementationAddress;
    address public tokenManagerAddress;
    address public tokenAddress;

    bytes data;

    address initialAdmin = makeAddr("initialAdmin");
    address agent = makeAddr("agent");
    address tokenOwner = makeAddr("tokenOwner");
    address tokenHolder = makeAddr("tokenHolder");
    address beneficiary = makeAddr("beneficiary");

    uint64 public constant ADMIN_ROLE = type(uint64).min;
    uint256 public constant AMOUNT = 1000 ether;

    function setUp() public {
        engineDeployer = new DeployEngine();
        (engineProxy, tokenImplementationAddress, tokenManagerAddress) = engineDeployer.run(initialAdmin);

        vm.startPrank(initialAdmin);
        BTtokensManager(tokenManagerAddress).grantRole(ADMIN_ROLE, engineProxy, 0);
        vm.stopPrank();

        BTtokensEngine_v1(engineProxy).initialize(address(this), tokenImplementationAddress, tokenManagerAddress);

        string memory tokenName = "BoulderTestToken";
        string memory tokenSymbol = "BTT";
        uint8 tokenDecimals = 18;

        data =
            abi.encode(engineProxy, tokenManagerAddress, tokenOwner, tokenHolder, tokenName, tokenSymbol, tokenDecimals);
        tokenAddress = BTtokensEngine_v1(engineProxy).createToken(tokenName, tokenSymbol, data, agent, tokenOwner);
        token = BTtokens_v1(tokenAddress);

        vm.prank(agent);
        token.mint(address(this), 1_000_000 ether);

        vestingImplementation = new BTvestingCliffWallet();
        factory = new BTvestingCliffWalletFactory(address(vestingImplementation));
    }

    function testCreateClone() public {
        uint64 start = uint64(block.timestamp);
        uint64 duration = 30 days;
        uint64 cliff = 10 days;

        address clone = factory.createVestingWallet(beneficiary, start, duration, cliff);

        assertTrue(clone != address(0));
        assertGt(clone.code.length, 0);
    }

    function testRevertsOnZeroAddress() public {
        vm.expectRevert();
        factory.createVestingWallet(address(0), uint64(block.timestamp), 10 days, 1 days);
    }

    function testRevertsIfNotOwner() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        factory.createVestingWallet(beneficiary, uint64(block.timestamp), 10 days, 1 days);
    }

    function testVestingReleasableAndRelease() public {
        skip(15 days); // simulate 15 days passed

        uint64 start = uint64(block.timestamp) - 15 days;
        uint64 duration = 30 days;
        uint64 cliff = 10 days;

        address clone = factory.createVestingWallet(beneficiary, start, duration, cliff);

        token.transfer(clone, 300 ether);

        uint256 releasableBefore = IVestingWalletClone(clone).releasable(address(token));
        assertGt(releasableBefore, 0);

        uint256 balanceBefore = token.balanceOf(beneficiary);

        vm.prank(beneficiary);
        IVestingWalletClone(clone).release(address(token));

        uint256 balanceAfter = token.balanceOf(beneficiary);
        assertEq(balanceAfter - balanceBefore, releasableBefore);
    }

    function testNothingReleasableBeforeCliff() public {
        uint64 start = uint64(block.timestamp);
        uint64 duration = 30 days;
        uint64 cliff = 10 days;

        address clone = factory.createVestingWallet(beneficiary, start, duration, cliff);
        token.transfer(clone, 300 ether);

        skip(5 days);

        uint256 releasable = IVestingWalletClone(clone).releasable(address(token));
        assertEq(releasable, 0);
    }

    function testAllTokensReleasableAfterEnd() public {
        uint64 start = uint64(block.timestamp);
        uint64 duration = 30 days;
        uint64 cliff = 10 days;

        address clone = factory.createVestingWallet(beneficiary, start, duration, cliff);
        token.transfer(clone, 300 ether);

        skip(40 days);

        uint256 releasable = IVestingWalletClone(clone).releasable(address(token));
        assertEq(releasable, 300 ether);
    }

    function testGradualVestingOverTime() public {
        uint64 start = uint64(block.timestamp);
        uint64 duration = 30 days;
        uint64 cliff = 10 days;

        address clone = factory.createVestingWallet(beneficiary, start, duration, cliff);
        token.transfer(clone, 300 ether);

        skip(15 days);
        uint256 releasableMid = IVestingWalletClone(clone).releasable(address(token));
        assertGt(releasableMid, 0);
        assertLt(releasableMid, 300 ether);

        vm.prank(beneficiary);
        IVestingWalletClone(clone).release(address(token));

        assertEq(token.balanceOf(beneficiary), releasableMid);

        skip(15 days);
        uint256 releasableAfter = IVestingWalletClone(clone).releasable(address(token));
        assertEq(releasableAfter, 300 ether - releasableMid);

        vm.prank(beneficiary);
        IVestingWalletClone(clone).release(address(token));
        assertEq(token.balanceOf(beneficiary), 300 ether);
    }
}
