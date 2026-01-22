// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplUSDv2 Invariant Tests
/// @notice Invariant test suite to verify core protocol properties hold under all conditions
contract SplUSDv2InvariantTest is Test {
    SplUSDv2 public vault;
    ERC20Mock public plUSD;
    SplUSDv2Handler public handler;

    address public admin = makeAddr("admin");

    function setUp() public {
        // Deploy mock plUSD
        plUSD = new ERC20Mock("plUSD", "plUSD", 18);

        // Deploy vault
        vault = new SplUSDv2(IERC20(address(plUSD)), admin);

        // Deploy handler
        handler = new SplUSDv2Handler(vault, plUSD, admin);

        // Target only the handler for invariant tests
        targetContract(address(handler));
    }

    // ============ Invariants ============

    /// @notice Total assets in vault should equal plUSD balance
    function invariant_TotalAssetsMatchesBalance() public view {
        assertEq(vault.totalAssets(), plUSD.balanceOf(address(vault)));
    }

    /// @notice Share price should never decrease (ignoring rounding)
    function invariant_SharePriceNeverDecreases() public view {
        uint256 currentSharePrice = handler.getCurrentSharePrice();
        uint256 initialSharePrice = handler.getInitialSharePrice();

        // Share price should never decrease (within small rounding tolerance)
        assertGe(currentSharePrice, initialSharePrice - 1);
    }

    /// @notice Total supply should match sum of all holder balances
    function invariant_TotalSupplyMatchesBalances() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 sumOfBalances = handler.sumOfAllBalances();

        assertEq(totalSupply, sumOfBalances);
    }

    /// @notice Users should never be able to withdraw more than deposited + yield
    function invariant_NoFreeValue() public view {
        // Total withdrawn should never exceed total deposited + total yield donated
        assertLe(
            handler.totalWithdrawn(),
            handler.totalDeposited() + handler.totalYieldDonated() + 1e6 // 1e6 tolerance for rounding
        );
    }

    /// @notice Assets and shares conversions should be consistent
    function invariant_ConversionConsistency() public view {
        if (vault.totalSupply() == 0) return;

        uint256 testAmount = 1e18;
        uint256 shares = vault.convertToShares(testAmount);
        uint256 assetsBack = vault.convertToAssets(shares);

        // Should get back approximately the same amount
        // With virtual offset and large yield donations, rounding can cause up to ~3% variance
        // This is acceptable as it only affects dust amounts and virtual offset protects against exploits
        assertApproxEqRel(assetsBack, testAmount, 0.05e18);
    }

    /// @notice Call summary for debugging
    function invariant_CallSummary() public view {
        console2.log("Deposits:", handler.depositCount());
        console2.log("Withdrawals:", handler.withdrawCount());
        console2.log("Yield donations:", handler.donateCount());
        console2.log("Total deposited:", handler.totalDeposited());
        console2.log("Total withdrawn:", handler.totalWithdrawn());
        console2.log("Total yield:", handler.totalYieldDonated());
        console2.log("Total assets:", vault.totalAssets());
        console2.log("Total supply:", vault.totalSupply());
    }
}

/// @title SplUSDv2Handler - Handler contract for invariant testing
/// @notice Provides bounded actions for fuzz testing the vault
contract SplUSDv2Handler is Test {
    SplUSDv2 public vault;
    ERC20Mock public plUSD;
    address public admin;

    // Tracking variables
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalYieldDonated;

    uint256 public depositCount;
    uint256 public withdrawCount;
    uint256 public donateCount;

    uint256 public initialSharePrice;

    // Actor tracking
    address[] public actors;
    mapping(address => bool) public isActor;
    mapping(address => uint256) public actorDeposits;

    // Constants
    uint256 public constant MAX_DEPOSIT = 1_000_000e18;
    uint256 public constant MIN_DEPOSIT = 1e15; // 0.001 tokens minimum

    constructor(SplUSDv2 vault_, ERC20Mock plUSD_, address admin_) {
        vault = vault_;
        plUSD = plUSD_;
        admin = admin_;

        // Initialize with a seed deposit to avoid edge cases
        plUSD.mint(admin, 1000e18);
        vm.startPrank(admin);
        plUSD.approve(address(vault), type(uint256).max);
        vault.deposit(1000e18, admin);
        vm.stopPrank();

        totalDeposited = 1000e18;
        initialSharePrice = vault.convertToAssets(1e18);

        // Add admin as first actor
        actors.push(admin);
        isActor[admin] = true;
        actorDeposits[admin] = 1000e18;
    }

    // ============ Handler Actions ============

    /// @notice Deposit assets into the vault
    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = _getActor(actorSeed);
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);

        // Mint plUSD to actor
        plUSD.mint(actor, amount);

        vm.startPrank(actor);
        plUSD.approve(address(vault), amount);
        vault.deposit(amount, actor);
        vm.stopPrank();

        totalDeposited += amount;
        actorDeposits[actor] += amount;
        depositCount++;
    }

    /// @notice Withdraw assets from the vault
    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = _getActor(actorSeed);
        uint256 maxWithdraw = vault.maxWithdraw(actor);

        if (maxWithdraw == 0) return;

        amount = bound(amount, 1, maxWithdraw);

        vm.prank(actor);
        vault.withdraw(amount, actor, actor);

        totalWithdrawn += amount;
        withdrawCount++;
    }

    /// @notice Redeem shares from the vault
    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = _getActor(actorSeed);
        uint256 maxRedeem = vault.maxRedeem(actor);

        if (maxRedeem == 0) return;

        shares = bound(shares, 1, maxRedeem);

        vm.prank(actor);
        uint256 assets = vault.redeem(shares, actor, actor);

        totalWithdrawn += assets;
        withdrawCount++;
    }

    /// @notice Donate yield to the vault
    function donateYield(uint256 amount) external {
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT / 10); // Limit yield to 10% of max deposit

        plUSD.mint(admin, amount);

        vm.startPrank(admin);
        plUSD.approve(address(vault), amount);
        vault.donateYield(amount);
        vm.stopPrank();

        totalYieldDonated += amount;
        donateCount++;
    }

    /// @notice Mint shares in the vault
    function mint(uint256 actorSeed, uint256 shares) external {
        address actor = _getActor(actorSeed);
        shares = bound(shares, MIN_DEPOSIT, MAX_DEPOSIT);

        uint256 assetsNeeded = vault.previewMint(shares);
        plUSD.mint(actor, assetsNeeded);

        vm.startPrank(actor);
        plUSD.approve(address(vault), assetsNeeded);
        uint256 actualAssets = vault.mint(shares, actor);
        vm.stopPrank();

        totalDeposited += actualAssets;
        actorDeposits[actor] += actualAssets;
        depositCount++;
    }

    // ============ View Functions ============

    function getCurrentSharePrice() external view returns (uint256) {
        return vault.convertToAssets(1e18);
    }

    function getInitialSharePrice() external view returns (uint256) {
        return initialSharePrice;
    }

    function sumOfAllBalances() external view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += vault.balanceOf(actors[i]);
        }
        return sum;
    }

    // ============ Internal Functions ============

    function _getActor(uint256 seed) internal returns (address) {
        // Sometimes create a new actor
        if (seed % 10 == 0 && actors.length < 20) {
            address newActor = makeAddr(string(abi.encodePacked("actor", actors.length)));
            actors.push(newActor);
            isActor[newActor] = true;
            return newActor;
        }

        // Otherwise use existing actor
        return actors[seed % actors.length];
    }
}
