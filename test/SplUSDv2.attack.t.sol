// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplUSDv2 Attack Tests
/// @notice Attempts to break the vault through various attack vectors
contract SplUSDv2AttackTest is Test {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    SplUSDv2 public vault;
    ERC20Mock public plUSD;

    address public deployer = makeAddr("deployer");
    address public attacker = makeAddr("attacker");
    address public victim = makeAddr("victim");
    address public alice = makeAddr("alice");

    uint256 public constant SEED_DEPOSIT = 1000e18;

    function setUp() public {
        plUSD = new ERC20Mock("plUSD", "plUSD", 18);
        vault = new SplUSDv2(IERC20(address(plUSD)));

        // Seed vault (standard deployment)
        plUSD.mint(deployer, SEED_DEPOSIT);
        vm.startPrank(deployer);
        plUSD.approve(address(vault), SEED_DEPOSIT);
        uint256 shares = vault.deposit(SEED_DEPOSIT, deployer);
        vault.transfer(DEAD, shares);
        vm.stopPrank();

        // Setup users
        vm.prank(attacker);
        plUSD.approve(address(vault), type(uint256).max);
        vm.prank(victim);
        plUSD.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        plUSD.approve(address(vault), type(uint256).max);
    }

    // ================================================================
    // INFLATION ATTACK TESTS
    // ================================================================

    /// @notice Classic inflation attack - should be mitigated by seed deposit
    function test_Attack_InflationAttack_Classic() public {
        // Attacker is first depositor after seed
        plUSD.mint(attacker, 1);
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(1, attacker);

        // Attacker donates large amount to inflate share price
        plUSD.mint(attacker, 10000e18);
        vm.prank(attacker);
        vault.donateYield(10000e18);

        // Victim deposits
        plUSD.mint(victim, 5000e18);
        vm.prank(victim);
        uint256 victimShares = vault.deposit(5000e18, victim);

        // Victim should get meaningful shares (not 0 or 1)
        assertGt(victimShares, 100e18, "Victim should get meaningful shares");

        // Victim should be able to withdraw most of their deposit
        vm.prank(victim);
        uint256 victimAssets = vault.redeem(victimShares, victim, victim);

        // Victim should lose less than 1% to the attack
        assertGt(victimAssets, 4950e18, "Victim should recover >99% of deposit");

        console2.log("Attacker shares:", attackerShares);
        console2.log("Victim shares:", victimShares);
        console2.log("Victim recovered:", victimAssets);
    }

    /// @notice Inflation attack variant - donate before any real deposits
    function test_Attack_InflationAttack_DonateFirst() public {
        // Attacker donates directly without depositing
        plUSD.mint(attacker, 100000e18);
        vm.prank(attacker);
        vault.donateYield(100000e18);

        // Share price is now inflated
        uint256 sharePriceAfterDonation = vault.convertToAssets(1e18);
        console2.log("Share price after donation:", sharePriceAfterDonation);

        // Victim deposits
        plUSD.mint(victim, 10000e18);
        vm.prank(victim);
        uint256 victimShares = vault.deposit(10000e18, victim);

        // Victim should still get meaningful shares
        assertGt(victimShares, 0, "Victim should get shares");

        // Victim can withdraw
        vm.prank(victim);
        uint256 victimAssets = vault.redeem(victimShares, victim, victim);

        // Victim should get back most of their deposit
        assertGt(victimAssets, 9900e18, "Victim should recover >99%");

        console2.log("Victim deposited: 10000e18");
        console2.log("Victim shares:", victimShares);
        console2.log("Victim recovered:", victimAssets);
    }

    // ================================================================
    // SANDWICH ATTACK TESTS
    // ================================================================

    /// @notice Sandwich attack on deposit - should not be profitable
    function test_Attack_SandwichDeposit() public {
        // Setup: Alice already has shares
        plUSD.mint(alice, 10000e18);
        vm.prank(alice);
        vault.deposit(10000e18, alice);

        // Attacker front-runs victim's deposit with large deposit
        plUSD.mint(attacker, 100000e18);
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(100000e18, attacker);

        uint256 attackerAssetsBefore = vault.convertToAssets(attackerShares);

        // Victim deposits
        plUSD.mint(victim, 10000e18);
        vm.prank(victim);
        vault.deposit(10000e18, victim);

        // Attacker back-runs by withdrawing
        uint256 attackerAssetsAfter = vault.convertToAssets(attackerShares);

        // Attacker should NOT profit from sandwich
        // (In a vault, deposits don't change share price, so no sandwich opportunity)
        assertEq(attackerAssetsBefore, attackerAssetsAfter, "No profit from sandwich");

        console2.log("Attacker assets before victim:", attackerAssetsBefore);
        console2.log("Attacker assets after victim:", attackerAssetsAfter);
    }

    /// @notice Sandwich attack on yield donation - check if exploitable
    function test_Attack_SandwichYieldDonation() public {
        // Setup: existing deposits
        plUSD.mint(alice, 10000e18);
        vm.prank(alice);
        vault.deposit(10000e18, alice);

        // Attacker deposits just before yield donation
        plUSD.mint(attacker, 100000e18);
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(100000e18, attacker);

        uint256 attackerAssetsBefore = vault.convertToAssets(attackerShares);

        // Someone donates yield
        plUSD.mint(deployer, 1000e18);
        vm.startPrank(deployer);
        plUSD.approve(address(vault), 1000e18);
        vault.donateYield(1000e18);
        vm.stopPrank();

        uint256 attackerAssetsAfter = vault.convertToAssets(attackerShares);

        // Attacker gets proportional share of yield - this is expected behavior, not an attack
        uint256 profit = attackerAssetsAfter - attackerAssetsBefore;

        // Profit should be proportional to their share of the pool
        // Attacker has ~90% of non-dead shares, so gets ~90% of yield
        console2.log("Attacker profit from yield:", profit);
        console2.log("This is expected - yield is distributed proportionally");

        // The "attack" here is just... depositing before yield. That's not exploitable
        // because the attacker has real capital at risk.
    }

    // ================================================================
    // FLASH LOAN ATTACK TESTS
    // ================================================================

    /// @notice Flash loan to manipulate share price - should not work
    function test_Attack_FlashLoanManipulation() public {
        // Setup: Alice deposits
        plUSD.mint(alice, 10000e18);
        vm.prank(alice);
        vault.deposit(10000e18, alice);

        // Attacker "flash loans" (simulated - gets tokens, must return same block)
        uint256 flashAmount = 1000000e18;
        plUSD.mint(attacker, flashAmount);

        vm.startPrank(attacker);

        // Deposit flash loaned amount
        uint256 shares = vault.deposit(flashAmount, attacker);

        // Immediately withdraw
        uint256 assetsBack = vault.redeem(shares, attacker, attacker);

        vm.stopPrank();

        // Should get back same amount (minus any rounding)
        assertApproxEqRel(assetsBack, flashAmount, 0.001e18, "Should get back same amount");

        // No profit possible from flash loan deposit/withdraw
        console2.log("Flash deposited:", flashAmount);
        console2.log("Got back:", assetsBack);
    }

    // ================================================================
    // ROUNDING ATTACK TESTS
    // ================================================================

    /// @notice Try to exploit rounding in small deposits
    function test_Attack_RoundingExploit_SmallDeposits() public {
        uint256 totalExtracted = 0;
        uint256 totalDeposited = 0;

        plUSD.mint(attacker, 1000e18);
        vm.startPrank(attacker);

        // Try many small deposits/withdrawals to extract rounding errors
        for (uint256 i = 0; i < 100; i++) {
            uint256 depositAmount = 1e15 + (i * 1e14); // Small varying amounts

            uint256 shares = vault.deposit(depositAmount, attacker);
            if (shares == 0) continue;

            totalDeposited += depositAmount;

            uint256 assets = vault.redeem(shares, attacker, attacker);
            totalExtracted += assets;
        }

        vm.stopPrank();

        // Should not be able to extract more than deposited
        assertLe(totalExtracted, totalDeposited + 100, "Cannot extract more than deposited");

        console2.log("Total deposited:", totalDeposited);
        console2.log("Total extracted:", totalExtracted);

        if (totalExtracted > totalDeposited) {
            console2.log("PROFIT:", totalExtracted - totalDeposited);
        } else {
            console2.log("LOSS:", totalDeposited - totalExtracted);
        }
    }

    /// @notice Try to exploit by depositing 1 wei repeatedly
    function test_Attack_OneWeiDeposits() public {
        plUSD.mint(attacker, 1000);
        vm.startPrank(attacker);

        uint256 totalShares = 0;
        uint256 successfulDeposits = 0;

        for (uint256 i = 0; i < 100; i++) {
            uint256 shares = vault.deposit(1, attacker);
            totalShares += shares;
            if (shares > 0) successfulDeposits++;
        }

        vm.stopPrank();

        console2.log("Successful 1-wei deposits:", successfulDeposits);
        console2.log("Total shares from 1-wei deposits:", totalShares);

        // With seed deposit, 1-wei deposits should still get some shares
        // but the rounding should favor the vault, not the attacker
    }

    // ================================================================
    // REENTRANCY TESTS
    // ================================================================

    /// @notice Test that donateYield is not vulnerable to reentrancy
    function test_Attack_Reentrancy_DonateYield() public {
        // Deploy malicious token that calls back on transfer
        ReentrantToken maliciousToken = new ReentrantToken("Evil", "EVIL", 18);

        // Deploy vault with malicious token
        SplUSDv2 maliciousVault = new SplUSDv2(IERC20(address(maliciousToken)));

        // Setup
        maliciousToken.mint(attacker, 10000e18);
        maliciousToken.setVault(address(maliciousVault));

        vm.startPrank(attacker);
        maliciousToken.approve(address(maliciousVault), type(uint256).max);

        // This should not allow reentrancy exploitation
        // The donateYield function uses safeTransferFrom which completes before
        // any state could be manipulated
        maliciousVault.deposit(1000e18, attacker);

        // Try to donate with reentrant token
        maliciousToken.setReentrant(true);

        // This might revert due to reentrancy attempt, which is fine
        try maliciousVault.donateYield(100e18) {
            // If it doesn't revert, the vault should still be consistent
            assertEq(
                maliciousVault.totalAssets(),
                maliciousToken.balanceOf(address(maliciousVault)),
                "Assets should match balance"
            );
        } catch {
            // Reentrancy was blocked - this is good
            console2.log("Reentrancy blocked");
        }

        vm.stopPrank();
    }

    // ================================================================
    // DONATION GRIEFING TESTS
    // ================================================================

    /// @notice Test if donating tiny amounts can grief the protocol
    function test_Attack_DonationGriefing() public {
        // Setup real depositor
        plUSD.mint(alice, 10000e18);
        vm.prank(alice);
        vault.deposit(10000e18, alice);

        uint256 aliceAssetsBefore = vault.convertToAssets(vault.balanceOf(alice));

        // Attacker spams tiny donations
        plUSD.mint(attacker, 1000);
        vm.startPrank(attacker);

        for (uint256 i = 0; i < 100; i++) {
            // donateYield requires amount > 0, so minimum is 1
            vault.donateYield(1);
        }

        vm.stopPrank();

        uint256 aliceAssetsAfter = vault.convertToAssets(vault.balanceOf(alice));

        // Alice's assets should only increase (she receives the donations)
        assertGe(aliceAssetsAfter, aliceAssetsBefore, "Donations should not decrease value");

        console2.log("Alice assets before griefing:", aliceAssetsBefore);
        console2.log("Alice assets after griefing:", aliceAssetsAfter);
        console2.log("Griefing cost to attacker: 100 wei");
        console2.log("Benefit to Alice:", aliceAssetsAfter - aliceAssetsBefore);
    }

    // ================================================================
    // SHARE MANIPULATION TESTS
    // ================================================================

    /// @notice Test if transferring shares can be exploited
    function test_Attack_ShareTransferExploit() public {
        // Alice deposits
        plUSD.mint(alice, 10000e18);
        vm.prank(alice);
        uint256 aliceShares = vault.deposit(10000e18, alice);

        // Yield is donated
        plUSD.mint(deployer, 1000e18);
        vm.startPrank(deployer);
        plUSD.approve(address(vault), 1000e18);
        vault.donateYield(1000e18);
        vm.stopPrank();

        // Alice transfers shares to attacker
        vm.prank(alice);
        vault.transfer(attacker, aliceShares);

        // Attacker redeems
        vm.prank(attacker);
        uint256 attackerAssets = vault.redeem(aliceShares, attacker, attacker);

        // Attacker gets the yield that was meant for Alice - but this is just
        // a normal transfer, not an exploit. The value follows the shares.
        console2.log("Alice deposited: 10000e18");
        console2.log("Yield donated: 1000e18");
        console2.log("Attacker received:", attackerAssets);

        // This is expected behavior - shares are transferable
        assertGt(attackerAssets, 10000e18, "Shares include yield");
    }

    // ================================================================
    // EXTREME VALUE TESTS
    // ================================================================

    /// @notice Test with maximum uint256 values
    function test_Attack_ExtremeValues() public {
        // Try to deposit near max uint256
        uint256 hugeAmount = type(uint128).max;
        plUSD.mint(attacker, hugeAmount);

        vm.startPrank(attacker);

        uint256 shares = vault.deposit(hugeAmount, attacker);
        assertGt(shares, 0, "Should get shares for huge deposit");

        uint256 assets = vault.redeem(shares, attacker, attacker);
        assertApproxEqRel(assets, hugeAmount, 0.001e18, "Should get back same amount");

        vm.stopPrank();

        console2.log("Deposited:", hugeAmount);
        console2.log("Shares:", shares);
        console2.log("Withdrawn:", assets);
    }

    /// @notice Test precision with very small values
    function test_Attack_PrecisionEdgeCases() public {
        // After huge donation, can small depositors still function?
        plUSD.mint(attacker, 1e30); // 1 trillion tokens
        vm.prank(attacker);
        vault.donateYield(1e30);

        // Now try small deposit
        plUSD.mint(victim, 1e18); // 1 token
        vm.prank(victim);
        uint256 shares = vault.deposit(1e18, victim);

        console2.log("After 1e30 donation, 1e18 deposit gets shares:", shares);

        if (shares > 0) {
            vm.prank(victim);
            uint256 assets = vault.redeem(shares, victim, victim);
            console2.log("Redeemed assets:", assets);
        }
    }

    // ================================================================
    // FRONT-RUNNING TESTS
    // ================================================================

    /// @notice Test if first deposit after deployment can be front-run
    function test_Attack_FrontRunFirstDeposit() public {
        // Deploy fresh vault without seed
        SplUSDv2 freshVault = new SplUSDv2(IERC20(address(plUSD)));

        // Attacker front-runs the first deposit
        plUSD.mint(attacker, 1);
        vm.prank(attacker);
        plUSD.approve(address(freshVault), type(uint256).max);
        vm.prank(attacker);
        uint256 attackerShares = freshVault.deposit(1, attacker);

        // Attacker inflates
        plUSD.mint(attacker, 10000e18);
        vm.prank(attacker);
        plUSD.approve(address(freshVault), type(uint256).max);
        vm.prank(attacker);
        freshVault.donateYield(10000e18);

        // Victim deposits
        plUSD.mint(victim, 5000e18);
        vm.prank(victim);
        plUSD.approve(address(freshVault), type(uint256).max);
        vm.prank(victim);
        uint256 victimShares = freshVault.deposit(5000e18, victim);

        console2.log("=== WITHOUT SEED DEPOSIT ===");
        console2.log("Attacker shares:", attackerShares);
        console2.log("Victim shares:", victimShares);

        // Without seed, victim might get 0 shares!
        // This demonstrates why the seed deposit is critical

        if (victimShares == 0) {
            console2.log("VULNERABLE: Victim got 0 shares!");
        } else {
            vm.prank(victim);
            uint256 victimAssets = freshVault.redeem(victimShares, victim, victim);
            console2.log("Victim recovered:", victimAssets);
        }
    }
}

/// @notice Malicious token for reentrancy testing
contract ReentrantToken is ERC20Mock {
    address public vault;
    bool public reentrant;

    constructor(string memory name, string memory symbol, uint8 decimals)
        ERC20Mock(name, symbol, decimals) {}

    function setVault(address _vault) external {
        vault = _vault;
    }

    function setReentrant(bool _reentrant) external {
        reentrant = _reentrant;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (reentrant && msg.sender == vault) {
            // Try to reenter
            try SplUSDv2(vault).donateYield(1) {
                // Reentrancy succeeded - bad!
            } catch {
                // Reentrancy blocked - good!
            }
        }
        return super.transferFrom(from, to, amount);
    }
}
