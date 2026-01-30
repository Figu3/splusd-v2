// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test, console2 } from "forge-std/Test.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "./mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SplUSDv2 Invariant Tests
/// @notice Invariant test suite to verify core protocol properties hold under all conditions
contract SplUSDv2InvariantTest is Test {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    SplUSDv2 public vault;
    ERC20Mock public plUSD;
    SplUSDv2Handler public handler;

    address public deployer = makeAddr("deployer");

    function setUp() public {
        plUSD = new ERC20Mock("plUSD", "plUSD", 18);
        vault = new SplUSDv2(IERC20(address(plUSD)));

        handler = new SplUSDv2Handler(vault, plUSD, deployer);

        targetContract(address(handler));
    }

    /// @notice Total assets in vault should equal plUSD balance
    function invariant_TotalAssetsMatchesBalance() public view {
        assertEq(vault.totalAssets(), plUSD.balanceOf(address(vault)));
    }

    /// @notice Share price should never decrease (ignoring rounding)
    function invariant_SharePriceNeverDecreases() public view {
        uint256 currentSharePrice = handler.getCurrentSharePrice();
        uint256 initialSharePrice = handler.getInitialSharePrice();

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
        assertLe(
            handler.totalWithdrawn(),
            handler.totalDeposited() + handler.totalYieldDonated() + 1e6
        );
    }

    /// @notice Assets and shares conversions should be consistent
    function invariant_ConversionConsistency() public view {
        // Skip if no real deposits beyond dead shares
        if (vault.totalAssets() < handler.SEED_DEPOSIT() + 1e18) return;

        uint256 testAmount = 1e18;
        uint256 shares = vault.convertToShares(testAmount);

        // Skip if shares would be 0 due to extreme price
        if (shares == 0) return;

        uint256 assetsBack = vault.convertToAssets(shares);

        assertApproxEqRel(assetsBack, testAmount, 0.05e18);
    }

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
contract SplUSDv2Handler is Test {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    SplUSDv2 public vault;
    ERC20Mock public plUSD;
    address public deployer;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public totalYieldDonated;

    uint256 public depositCount;
    uint256 public withdrawCount;
    uint256 public donateCount;

    uint256 public initialSharePrice;

    address[] public actors;
    mapping(address => bool) public isActor;
    mapping(address => uint256) public actorDeposits;

    uint256 public constant MAX_DEPOSIT = 1_000_000e18;
    uint256 public constant MIN_DEPOSIT = 1e15;
    uint256 public constant SEED_DEPOSIT = 1000e18;

    constructor(SplUSDv2 vault_, ERC20Mock plUSD_, address deployer_) {
        vault = vault_;
        plUSD = plUSD_;
        deployer = deployer_;

        // Seed vault with initial deposit burned to 0xdead
        plUSD.mint(deployer, SEED_DEPOSIT);
        vm.startPrank(deployer);
        plUSD.approve(address(vault), SEED_DEPOSIT);
        uint256 shares = vault.deposit(SEED_DEPOSIT, deployer);
        vault.transfer(DEAD, shares);
        vm.stopPrank();

        totalDeposited = SEED_DEPOSIT;
        initialSharePrice = vault.convertToAssets(1e18);

        // Add dead address as actor (holds seed shares)
        actors.push(DEAD);
        isActor[DEAD] = true;
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = _getActor(actorSeed);
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);

        plUSD.mint(actor, amount);

        vm.startPrank(actor);
        plUSD.approve(address(vault), amount);
        vault.deposit(amount, actor);
        vm.stopPrank();

        totalDeposited += amount;
        actorDeposits[actor] += amount;
        depositCount++;
    }

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

    function donateYield(uint256 amount) external {
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT / 10);

        plUSD.mint(deployer, amount);

        vm.startPrank(deployer);
        plUSD.approve(address(vault), amount);
        vault.donateYield(amount);
        vm.stopPrank();

        totalYieldDonated += amount;
        donateCount++;
    }

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

    function _getActor(uint256 seed) internal returns (address) {
        if (seed % 10 == 0 && actors.length < 20) {
            address newActor = makeAddr(string(abi.encodePacked("actor", actors.length)));
            actors.push(newActor);
            isActor[newActor] = true;
            return newActor;
        }

        return actors[seed % actors.length];
    }
}
