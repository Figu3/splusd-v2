// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplUSDv2 Unit Tests
/// @notice Comprehensive test suite for the splUSD v2 staking vault
contract SplUSDv2Test is Test {
    // ============ State ============

    SplUSDv2 public vault;
    ERC20Mock public plUSD;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant INITIAL_BALANCE = 1_000_000e18;

    // ============ Events ============

    event YieldDonated(address indexed donor, uint256 amount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Paused(address account);
    event Unpaused(address account);

    // ============ Setup ============

    function setUp() public {
        // Deploy mock plUSD
        plUSD = new ERC20Mock("plUSD", "plUSD", 18);

        // Deploy vault
        vault = new SplUSDv2(IERC20(address(plUSD)), admin);

        // Mint plUSD to test users
        plUSD.mint(alice, INITIAL_BALANCE);
        plUSD.mint(bob, INITIAL_BALANCE);
        plUSD.mint(charlie, INITIAL_BALANCE);
        plUSD.mint(admin, INITIAL_BALANCE);

        // Approve vault for all users
        vm.prank(alice);
        plUSD.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        plUSD.approve(address(vault), type(uint256).max);

        vm.prank(charlie);
        plUSD.approve(address(vault), type(uint256).max);

        vm.prank(admin);
        plUSD.approve(address(vault), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(vault.name(), "Staked plUSD v2");
        assertEq(vault.symbol(), "splUSD");
        // Decimals = underlying decimals (18) + offset (6) = 24
        assertEq(vault.decimals(), 24);
        assertEq(vault.asset(), address(plUSD));
        assertEq(vault.owner(), admin);
        assertEq(vault.paused(), false);
    }

    function test_Constructor_RevertZeroPlUSD() public {
        vm.expectRevert("SplUSDv2: zero plUSD address");
        new SplUSDv2(IERC20(address(0)), admin);
    }

    function test_Constructor_RevertZeroAdmin() public {
        // OpenZeppelin Ownable reverts with OwnableInvalidOwner for zero address
        vm.expectRevert(abi.encodeWithSignature("OwnableInvalidOwner(address)", address(0)));
        new SplUSDv2(IERC20(address(plUSD)), address(0));
    }

    // ============ Deposit Tests ============

    function test_Deposit() public {
        uint256 depositAmount = 1000e18;

        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        // With virtual offset of 1e6, first deposit should get slightly less shares
        // shares = assets * (totalSupply + 1e6) / (totalAssets + 1)
        // For first deposit: shares ≈ assets (with small offset adjustment)
        assertGt(shares, 0);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(plUSD.balanceOf(address(vault)), depositAmount);
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

        // Both should get similar shares (Alice slightly more due to virtual offset math)
        assertApproxEqRel(aliceShares, bobShares, 0.001e18); // Within 0.1%
        assertEq(plUSD.balanceOf(address(vault)), depositAmount * 2);
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
        assertApproxEqAbs(plUSD.balanceOf(alice), INITIAL_BALANCE, 1); // Allow 1 wei rounding
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
        assertApproxEqAbs(
            plUSD.balanceOf(alice),
            INITIAL_BALANCE - depositAmount + withdrawAmount,
            1
        );
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

        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 shareValueBefore = vault.convertToAssets(1e18);

        // Admin donates yield
        vm.prank(admin);
        vault.donateYield(yieldAmount);

        uint256 shareValueAfter = vault.convertToAssets(1e18);

        // Share value should increase
        assertGt(shareValueAfter, shareValueBefore);
        assertEq(vault.totalAssets(), depositAmount + yieldAmount);
    }

    function test_DonateYield_EmitsEvent() public {
        uint256 yieldAmount = 100e18;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit YieldDonated(admin, yieldAmount);
        vault.donateYield(yieldAmount);
    }

    function test_DonateYield_RevertZeroAmount() public {
        vm.prank(admin);
        vm.expectRevert("SplUSDv2: zero amount");
        vault.donateYield(0);
    }

    function test_DonateYield_AnyoneCanDonate() public {
        uint256 yieldAmount = 100e18;

        // Non-admin (alice) can also donate
        vm.prank(alice);
        vault.donateYield(yieldAmount);

        assertEq(vault.totalAssets(), yieldAmount);
    }

    function test_DonateYield_ShareValueIncrease() public {
        uint256 depositAmount = 10000e18;
        uint256 yieldAmount = 1000e18; // 10% yield

        // Alice deposits
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 aliceAssetsBefore = vault.convertToAssets(vault.balanceOf(alice));

        // Admin donates 10% yield
        vm.prank(admin);
        vault.donateYield(yieldAmount);

        uint256 aliceAssetsAfter = vault.convertToAssets(vault.balanceOf(alice));

        // Alice's assets should be ~10% higher
        assertApproxEqRel(aliceAssetsAfter, aliceAssetsBefore + yieldAmount, 0.001e18);
    }

    function test_DonateYield_MultipleStakers() public {
        uint256 aliceDeposit = 7000e18;
        uint256 bobDeposit = 3000e18;
        uint256 yieldAmount = 1000e18;

        // Alice and Bob deposit
        vm.prank(alice);
        vault.deposit(aliceDeposit, alice);

        vm.prank(bob);
        vault.deposit(bobDeposit, bob);

        uint256 aliceSharesBefore = vault.balanceOf(alice);
        uint256 bobSharesBefore = vault.balanceOf(bob);

        // Admin donates yield
        vm.prank(admin);
        vault.donateYield(yieldAmount);

        // Shares don't change
        assertEq(vault.balanceOf(alice), aliceSharesBefore);
        assertEq(vault.balanceOf(bob), bobSharesBefore);

        // But asset values increase proportionally
        uint256 aliceAssets = vault.convertToAssets(aliceSharesBefore);
        uint256 bobAssets = vault.convertToAssets(bobSharesBefore);

        // Alice had 70% of deposits, should get ~70% of yield
        assertApproxEqRel(aliceAssets, aliceDeposit + (yieldAmount * 70 / 100), 0.01e18);
        // Bob had 30% of deposits, should get ~30% of yield
        assertApproxEqRel(bobAssets, bobDeposit + (yieldAmount * 30 / 100), 0.01e18);
    }

    // ============ Pause Tests ============

    function test_Pause() public {
        vm.prank(admin);
        vault.pause();

        assertTrue(vault.paused());
    }

    function test_Pause_EmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit Paused(admin);
        vault.pause();
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vault.pause();
    }

    function test_Unpause() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(admin);
        vault.unpause();

        assertFalse(vault.paused());
    }

    function test_Unpause_OnlyOwner() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vault.unpause();
    }

    function test_Pause_BlocksDeposit() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vault.deposit(1000e18, alice);
    }

    function test_Pause_BlocksMint() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vault.mint(1000e18, alice);
    }

    function test_Pause_BlocksWithdraw() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vault.withdraw(500e18, alice, alice);
    }

    function test_Pause_BlocksRedeem() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e18, alice);

        vm.prank(admin);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vault.redeem(shares, alice, alice);
    }

    function test_Pause_MaxDepositReturnsZero() public {
        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_Pause_MaxMintReturnsZero() public {
        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxMint(alice), 0);
    }

    function test_Pause_MaxWithdrawReturnsZero() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_Pause_MaxRedeemReturnsZero() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxRedeem(alice), 0);
    }

    function test_Pause_DonateYieldStillWorks() public {
        vm.prank(admin);
        vault.pause();

        // Donating yield should still work when paused
        vm.prank(admin);
        vault.donateYield(100e18);

        assertEq(vault.totalAssets(), 100e18);
    }

    // ============ Ownership Tests ============

    function test_TransferOwnership_TwoStep() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(admin);
        vault.transferOwnership(newAdmin);

        // Still old admin until accepted
        assertEq(vault.owner(), admin);

        vm.prank(newAdmin);
        vault.acceptOwnership();

        assertEq(vault.owner(), newAdmin);
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
        // Attacker deposits minimal amount
        vm.prank(alice);
        vault.deposit(1, alice);

        // Attacker tries to donate large amount to inflate share price
        plUSD.mint(alice, 1000e18);
        vm.prank(alice);
        vault.donateYield(1000e18);

        // Victim deposits
        vm.prank(bob);
        uint256 bobShares = vault.deposit(1000e18, bob);

        // With virtual offset protection, Bob should get meaningful shares
        assertGt(bobShares, 0);

        // Bob should be able to withdraw most of their deposit
        vm.prank(bob);
        uint256 bobAssets = vault.redeem(bobShares, bob, bob);

        // Bob should get back a significant portion (not lose everything to rounding)
        assertGt(bobAssets, 900e18); // Should get back >90% at least
    }

    // ============ Edge Case Tests ============

    function test_ZeroTotalSupply_ConvertToShares() public view {
        // With virtual offset, conversion should still work
        uint256 shares = vault.convertToShares(1000e18);
        assertGt(shares, 0);
    }

    function test_ZeroTotalSupply_ConvertToAssets() public view {
        // With virtual offset, conversion should still work
        uint256 assets = vault.convertToAssets(1000e18);
        assertGt(assets, 0);
    }
}
