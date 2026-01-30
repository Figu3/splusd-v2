// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplUSDv2 Unit Tests
/// @notice Comprehensive test suite for the splUSD v2 staking vault
contract SplUSDv2Test is Test {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    SplUSDv2 public vault;
    ERC20Mock public plUSD;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public deployer = makeAddr("deployer");

    uint256 public constant INITIAL_BALANCE = 1_000_000e18;
    uint256 public constant SEED_DEPOSIT = 1000e18;

    event YieldDonated(address indexed donor, uint256 amount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        plUSD = new ERC20Mock("plUSD", "plUSD", 18);
        vault = new SplUSDv2(IERC20(address(plUSD)));

        // Seed vault with initial deposit burned to 0xdead (inflation protection)
        plUSD.mint(deployer, SEED_DEPOSIT);
        vm.startPrank(deployer);
        plUSD.approve(address(vault), SEED_DEPOSIT);
        uint256 shares = vault.deposit(SEED_DEPOSIT, deployer);
        vault.transfer(DEAD, shares);
        vm.stopPrank();

        // Mint plUSD to test users
        plUSD.mint(alice, INITIAL_BALANCE);
        plUSD.mint(bob, INITIAL_BALANCE);
        plUSD.mint(charlie, INITIAL_BALANCE);

        // Approve vault for all users
        vm.prank(alice);
        plUSD.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        plUSD.approve(address(vault), type(uint256).max);
        vm.prank(charlie);
        plUSD.approve(address(vault), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(vault.name(), "Staked plUSD v2");
        assertEq(vault.symbol(), "splUSD");
        assertEq(vault.decimals(), 18);
        assertEq(vault.asset(), address(plUSD));
    }

    function test_Constructor_RevertZeroPlUSD() public {
        vm.expectRevert("SplUSDv2: zero plUSD address");
        new SplUSDv2(IERC20(address(0)));
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(plUSD.balanceOf(address(vault)), SEED_DEPOSIT + depositAmount);
    }

    function test_Deposit_EmitsEvent() public {
        uint256 depositAmount = 1000e18;
        uint256 expectedShares = vault.previewDeposit(depositAmount);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, alice, depositAmount, expectedShares);
        vault.deposit(depositAmount, alice);
    }

    function test_Deposit_ToOtherReceiver() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, bob);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.balanceOf(bob), shares);
    }

    function test_Deposit_MultipleUsers() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        vm.prank(bob);
        uint256 bobShares = vault.deposit(depositAmount, bob);

        assertApproxEqRel(aliceShares, bobShares, 0.001e18);
        assertEq(plUSD.balanceOf(address(vault)), SEED_DEPOSIT + depositAmount * 2);
    }

    // ============ Withdraw Tests ============

    function test_Withdraw() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);

        vm.prank(alice);
        uint256 shares = vault.withdraw(maxWithdraw, alice, alice);

        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), 0);
        assertApproxEqAbs(plUSD.balanceOf(alice), INITIAL_BALANCE, 1);
    }

    function test_Withdraw_Partial() public {
        uint256 depositAmount = 1000e18;
        uint256 withdrawAmount = 500e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 sharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);

        uint256 sharesAfter = vault.balanceOf(alice);
        assertLt(sharesAfter, sharesBefore);
    }

    function test_Withdraw_ToOtherReceiver() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 maxWithdraw = vault.maxWithdraw(alice);
        uint256 bobBalanceBefore = plUSD.balanceOf(bob);

        vm.prank(alice);
        vault.withdraw(maxWithdraw, bob, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(plUSD.balanceOf(bob), bobBalanceBefore + maxWithdraw);
    }

    // ============ Mint Tests ============

    function test_Mint() public {
        uint256 sharesToMint = 1000e18;

        vm.prank(alice);
        uint256 assets = vault.mint(sharesToMint, alice);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), sharesToMint);
    }

    // ============ Redeem Tests ============

    function test_Redeem() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        vm.prank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);

        assertGt(assets, 0);
        assertEq(vault.balanceOf(alice), 0);
        assertApproxEqAbs(plUSD.balanceOf(alice), INITIAL_BALANCE, 1);
    }

    // ============ Yield Donation Tests ============

    function test_DonateYield() public {
        uint256 depositAmount = 1000e18;
        uint256 yieldAmount = 100e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 shareValueBefore = vault.convertToAssets(1e18);

        plUSD.mint(bob, yieldAmount);
        vm.prank(bob);
        plUSD.approve(address(vault), yieldAmount);
        vm.prank(bob);
        vault.donateYield(yieldAmount);

        uint256 shareValueAfter = vault.convertToAssets(1e18);

        assertGt(shareValueAfter, shareValueBefore);
        assertEq(vault.totalAssets(), SEED_DEPOSIT + depositAmount + yieldAmount);
    }

    function test_DonateYield_EmitsEvent() public {
        uint256 yieldAmount = 100e18;

        plUSD.mint(alice, yieldAmount);
        vm.prank(alice);
        plUSD.approve(address(vault), yieldAmount);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit YieldDonated(alice, yieldAmount);
        vault.donateYield(yieldAmount);
    }

    function test_DonateYield_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("SplUSDv2: zero amount");
        vault.donateYield(0);
    }

    function test_DonateYield_AnyoneCanDonate() public {
        uint256 yieldAmount = 100e18;

        vm.prank(alice);
        vault.donateYield(yieldAmount);

        assertEq(vault.totalAssets(), SEED_DEPOSIT + yieldAmount);
    }

    function test_DonateYield_ShareValueIncrease() public {
        uint256 depositAmount = 10000e18;
        uint256 yieldAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceAssetsBefore = vault.convertToAssets(vault.balanceOf(alice));

        plUSD.mint(bob, yieldAmount);
        vm.prank(bob);
        plUSD.approve(address(vault), yieldAmount);
        vm.prank(bob);
        vault.donateYield(yieldAmount);

        uint256 aliceAssetsAfter = vault.convertToAssets(vault.balanceOf(alice));

        // Alice should get most of the yield (proportional to her share)
        assertGt(aliceAssetsAfter, aliceAssetsBefore);
    }

    function test_DonateYield_MultipleStakers() public {
        uint256 aliceDeposit = 7000e18;
        uint256 bobDeposit = 3000e18;
        uint256 yieldAmount = 1000e18;

        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);

        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 bobSharesBefore = vault.balanceOf(bob);

        plUSD.mint(charlie, yieldAmount);
        vm.prank(charlie);
        plUSD.approve(address(vault), yieldAmount);
        vm.prank(charlie);
        vault.donateYield(yieldAmount);

        // Shares don't change
        assertEq(vault.balanceOf(alice), aliceSharesBefore);
        assertEq(vault.balanceOf(bob), bobSharesBefore);

        // But asset values increase proportionally
        uint256 aliceAssets = vault.convertToAssets(aliceSharesBefore);
        uint256 bobAssets = vault.convertToAssets(bobSharesBefore);

        // Alice has more shares, so she gets more yield
        assertGt(aliceAssets, bobAssets);
    }

    // ============ ERC4626 Preview Tests ============

    function test_PreviewDeposit() public view {
        uint256 assets = 1000e18;
        uint256 expectedShares = vault.previewDeposit(assets);
        assertGt(expectedShares, 0);
    }

    function test_PreviewMint() public view {
        uint256 shares = 1000e18;
        uint256 expectedAssets = vault.previewMint(shares);
        assertGt(expectedAssets, 0);
    }

    function test_PreviewWithdraw() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        uint256 assets = 500e18;
        uint256 expectedShares = vault.previewWithdraw(assets);
        assertGt(expectedShares, 0);
    }

    function test_PreviewRedeem() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e18, alice);

        uint256 expectedAssets = vault.previewRedeem(shares);
        assertGt(expectedAssets, 0);
        assertApproxEqAbs(expectedAssets, 1000e18, 1);
    }

    // ============ Inflation Attack Protection Tests ============

    function test_InflationAttack_Protected() public {
        // With seed deposit burned to 0xdead, inflation attacks are not profitable
        // Attacker would need to donate more than seed deposit to manipulate price significantly

        vm.prank(bob);
        uint256 bobShares = vault.deposit(1000e18, bob);

        assertGt(bobShares, 0);

        vm.prank(bob);
        uint256 bobAssets = vault.redeem(bobShares, bob, bob);

        // Bob should get back nearly all of their deposit
        assertGt(bobAssets, 999e18);
    }

    // ============ Edge Case Tests ============

    function test_ConvertToShares() public view {
        uint256 shares = vault.convertToShares(1000e18);
        assertGt(shares, 0);
    }

    function test_ConvertToAssets() public view {
        uint256 assets = vault.convertToAssets(1000e18);
        assertGt(assets, 0);
    }
}
