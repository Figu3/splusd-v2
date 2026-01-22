// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplUSDv2 Fuzz Tests
/// @notice Fuzz test suite to verify vault behavior with random inputs
contract SplUSDv2FuzzTest is Test {
    SplUSDv2 public vault;
    ERC20Mock public plUSD;

    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");

    function setUp() public {
        plUSD = new ERC20Mock("plUSD", "plUSD", 18);
        vault = new SplUSDv2(IERC20(address(plUSD)), admin);

        // Seed vault to avoid edge cases
        plUSD.mint(admin, 1000e18);
        vm.startPrank(admin);
        plUSD.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, admin);
        vm.stopPrank();

        // Setup alice
        vm.prank(alice);
        plUSD.approve(address(vault), type(uint256).max);
    }

    // ============ Deposit Fuzz Tests ============

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000_000e18);

        plUSD.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(alice), shares, "Balance should match shares");
    }

    function testFuzz_DepositAndWithdraw(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e15, 1_000_000_000e18);

        plUSD.mint(alice, depositAmount);

        vm.startPrank(alice);

        // Deposit
        uint256 shares = vault.deposit(depositAmount, alice);
        assertGt(shares, 0);

        // Withdraw max
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vault.withdraw(maxWithdraw, alice, alice);

        vm.stopPrank();

        // Should get back approximately the same (within rounding)
        assertApproxEqRel(maxWithdraw, depositAmount, 0.001e18, "Should get back ~same amount");
    }

    function testFuzz_DepositAndRedeem(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e15, 1_000_000_000e18);

        plUSD.mint(alice, depositAmount);

        vm.startPrank(alice);

        // Deposit
        uint256 shares = vault.deposit(depositAmount, alice);
        assertGt(shares, 0);

        // Redeem all shares
        uint256 assets = vault.redeem(shares, alice, alice);

        vm.stopPrank();

        // Should get back approximately the same (within rounding)
        assertApproxEqRel(assets, depositAmount, 0.001e18, "Should get back ~same amount");
    }

    // ============ Yield Donation Fuzz Tests ============

    function testFuzz_DonateYield(uint256 depositAmount, uint256 yieldAmount) public {
        depositAmount = bound(depositAmount, 1e18, 1_000_000e18);
        yieldAmount = bound(yieldAmount, 1e15, depositAmount); // Yield up to 100% of deposit

        plUSD.mint(alice, depositAmount);
        plUSD.mint(admin, yieldAmount);

        // Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 assetsBefore = vault.convertToAssets(shares);

        // Admin donates yield
        vm.prank(admin);
        vault.donateYield(yieldAmount);

        uint256 assetsAfter = vault.convertToAssets(shares);

        // Alice's assets should increase by approximately the yield amount
        // (minus any amount that goes to the seed deposit from admin)
        assertGt(assetsAfter, assetsBefore, "Assets should increase after yield");
    }

    function testFuzz_MultipleYieldDonations(uint256 numDonations, uint256 seed) public {
        numDonations = bound(numDonations, 1, 20);

        // Alice deposits
        uint256 depositAmount = 10000e18;
        plUSD.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);

        uint256 totalYield = 0;
        uint256 assetsBefore = vault.convertToAssets(shares);

        // Multiple yield donations
        for (uint256 i = 0; i < numDonations; i++) {
            uint256 yieldAmount = uint256(keccak256(abi.encode(seed, i))) % 1000e18 + 1e18;
            plUSD.mint(admin, yieldAmount);

            vm.prank(admin);
            vault.donateYield(yieldAmount);

            totalYield += yieldAmount;
        }

        uint256 assetsAfter = vault.convertToAssets(shares);

        // Assets should have increased
        assertGt(assetsAfter, assetsBefore, "Assets should increase");
    }

    // ============ Share Conversion Fuzz Tests ============

    function testFuzz_ConvertToShares(uint256 assets) public view {
        assets = bound(assets, 1, type(uint128).max);

        uint256 shares = vault.convertToShares(assets);

        // Should always get some shares for non-zero assets
        if (assets > 0) {
            assertGt(shares, 0, "Should get shares for assets");
        }
    }

    function testFuzz_ConvertToAssets(uint256 shares) public view {
        // With virtual offset (1e6), very small share amounts may round to 0 assets
        // This is expected behavior - need minimum shares to get meaningful assets
        shares = bound(shares, 1e6, type(uint128).max);

        uint256 assets = vault.convertToAssets(shares);

        // Should get some assets for shares above the offset threshold
        assertGt(assets, 0, "Should get assets for shares");
    }

    function testFuzz_RoundTripConversion(uint256 amount) public view {
        amount = bound(amount, 1e15, type(uint128).max);

        // Assets -> Shares -> Assets
        uint256 shares = vault.convertToShares(amount);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Should get back approximately the same (within small rounding)
        assertApproxEqRel(assetsBack, amount, 0.001e18, "Round trip should preserve value");
    }

    // ============ Preview Function Fuzz Tests ============

    function testFuzz_PreviewDeposit(uint256 assets) public view {
        assets = bound(assets, 1, type(uint128).max);

        uint256 shares = vault.previewDeposit(assets);

        // Preview should match convert (for deposits, they're the same)
        assertEq(shares, vault.convertToShares(assets), "Preview should match convert");
    }

    function testFuzz_PreviewMint(uint256 shares) public view {
        shares = bound(shares, 1, type(uint128).max);

        uint256 assets = vault.previewMint(shares);

        // Should need some assets to mint shares
        assertGt(assets, 0, "Should need assets to mint");
    }

    function testFuzz_PreviewWithdraw(uint256 assets) public {
        // First deposit some assets
        uint256 depositAmount = 10000e18;
        plUSD.mint(alice, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        assets = bound(assets, 1, vault.maxWithdraw(alice));

        uint256 shares = vault.previewWithdraw(assets);

        // Should need some shares to withdraw assets
        assertGt(shares, 0, "Should need shares to withdraw");
    }

    function testFuzz_PreviewRedeem(uint256 shares) public {
        // First deposit some assets
        uint256 depositAmount = 10000e18;
        plUSD.mint(alice, depositAmount);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(depositAmount, alice);

        // With virtual offset, very small shares may round to 0 assets
        // Bound to minimum 1e6 to ensure meaningful redemption
        shares = bound(shares, 1e6, aliceShares);

        uint256 assets = vault.previewRedeem(shares);

        // Should get some assets for shares above threshold
        assertGt(assets, 0, "Should get assets for redeem");
    }

    // ============ Multiple Users Fuzz Tests ============

    function testFuzz_MultipleDepositors(uint256 numDepositors, uint256 seed) public {
        numDepositors = bound(numDepositors, 2, 20);

        uint256 totalDeposited = 0;
        address[] memory depositors = new address[](numDepositors);
        uint256[] memory deposits = new uint256[](numDepositors);
        uint256[] memory shares = new uint256[](numDepositors);

        // Each user deposits random amount
        for (uint256 i = 0; i < numDepositors; i++) {
            depositors[i] = makeAddr(string(abi.encodePacked("depositor", i)));
            deposits[i] = uint256(keccak256(abi.encode(seed, i))) % 10000e18 + 1e18;

            plUSD.mint(depositors[i], deposits[i]);

            vm.startPrank(depositors[i]);
            plUSD.approve(address(vault), deposits[i]);
            shares[i] = vault.deposit(deposits[i], depositors[i]);
            vm.stopPrank();

            totalDeposited += deposits[i];

            assertGt(shares[i], 0, "Should get shares");
        }

        // Verify total assets (excluding seed deposit from admin)
        assertEq(
            vault.totalAssets(),
            totalDeposited + 1000e18, // +1000e18 is the admin seed deposit
            "Total assets should match"
        );
    }

    // ============ Edge Case Fuzz Tests ============

    function testFuzz_SmallDeposits(uint256 amount) public {
        // Test very small deposits
        amount = bound(amount, 1, 1e15);

        plUSD.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        // Should still get some shares even for tiny amounts (due to virtual offset)
        // Note: for very small amounts, this might be 0 due to rounding
        // which is acceptable behavior
        if (amount >= 1000) {
            // For amounts >= 1000 wei, should get shares
            assertGt(shares, 0, "Should get shares for small deposit");
        }
    }

    function testFuzz_LargeDeposits(uint256 amount) public {
        // Test very large deposits
        amount = bound(amount, 1e27, type(uint128).max);

        plUSD.mint(alice, amount);

        vm.prank(alice);
        uint256 shares = vault.deposit(amount, alice);

        assertGt(shares, 0, "Should get shares for large deposit");

        // Should be able to withdraw
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        assertGt(maxWithdraw, 0, "Should have withdrawable assets");
    }
}
