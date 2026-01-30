// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { ERC20Mock } from "../test/mocks/ERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Deploy Script for Sepolia Testnet
/// @notice Deploys mock plUSD + SplUSDv2 vault for testing
contract DeploySepoliaScript is Script {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant SEED_DEPOSIT = 1000e18;
    uint256 public constant MOCK_MINT = 100_000e18; // Mint extra for testing

    function run() public returns (ERC20Mock mockPlUSD, SplUSDv2 vault) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("=== Sepolia Testnet Deployment ===");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy mock plUSD
        mockPlUSD = new ERC20Mock("Mock plUSD", "plUSD", 18);
        console2.log("Mock plUSD deployed at:", address(mockPlUSD));

        // 2. Mint plUSD to deployer
        mockPlUSD.mint(deployer, MOCK_MINT);
        console2.log("Minted", MOCK_MINT / 1e18, "plUSD to deployer");

        // 3. Deploy vault
        vault = new SplUSDv2(IERC20(address(mockPlUSD)));
        console2.log("SplUSDv2 deployed at:", address(vault));

        // 4. Seed deposit + burn for inflation protection
        mockPlUSD.approve(address(vault), SEED_DEPOSIT);
        uint256 shares = vault.deposit(SEED_DEPOSIT, deployer);
        require(shares > 0, "No shares minted");

        bool success = vault.transfer(DEAD, shares);
        require(success, "Transfer to dead failed");

        console2.log("Seed shares burned to dead:", shares);

        vm.stopBroadcast();

        // 5. Post-deployment verification
        require(vault.balanceOf(DEAD) == shares, "Dead address missing shares");
        require(vault.balanceOf(deployer) == 0, "Deployer still has shares");
        require(vault.totalSupply() == shares, "Unexpected total supply");
        require(vault.totalAssets() == SEED_DEPOSIT, "Unexpected total assets");

        console2.log("");
        console2.log("=== Verification Passed ===");
        console2.log("");
        console2.log("Deployer plUSD balance:", mockPlUSD.balanceOf(deployer) / 1e18);
        console2.log("");
        console2.log("=== Contract Addresses ===");
        console2.log("Mock plUSD:", address(mockPlUSD));
        console2.log("SplUSDv2:  ", address(vault));

        return (mockPlUSD, vault);
    }
}
