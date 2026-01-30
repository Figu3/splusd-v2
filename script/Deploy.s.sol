// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Deploy Script for SplUSDv2
/// @notice Deploys the splUSD v2 vault with inflation attack protection
/// @dev Seeds vault with initial deposit and burns shares to 0xdead
contract DeployScript is Script {
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // Plasma Mainnet addresses
    address public constant PLASMA_PLUSD = 0xf91c31299E998C5127Bc5F11e4a657FC0cF358CD;

    // Deployment parameters
    address public plUSD;
    uint256 public seedDeposit;

    function setUp() public virtual {
        plUSD = vm.envOr("PLUSD_ADDRESS", PLASMA_PLUSD);
        seedDeposit = vm.envOr("SEED_DEPOSIT", uint256(10e18)); // 10 plUSD
    }

    function run() public returns (SplUSDv2 vault) {
        require(plUSD != address(0), "plUSD address not set");
        require(seedDeposit > 0, "Seed deposit required for inflation protection");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying SplUSDv2...");
        console2.log("  plUSD:", plUSD);
        console2.log("  Seed deposit:", seedDeposit);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy vault
        vault = new SplUSDv2(IERC20(plUSD));
        console2.log("  Vault deployed at:", address(vault));

        // Seed deposit + burn to 0xdead for inflation attack protection
        IERC20(plUSD).approve(address(vault), seedDeposit);
        uint256 shares = vault.deposit(seedDeposit, deployer);
        require(shares > 0, "No shares minted");

        bool success = vault.transfer(DEAD, shares);
        require(success, "Transfer to dead failed");

        console2.log("  Shares burned to dead:", shares);

        vm.stopBroadcast();

        // Post-deployment verification
        require(vault.balanceOf(DEAD) == shares, "Dead address missing shares");
        require(vault.balanceOf(deployer) == 0, "Deployer still has shares");
        require(vault.totalSupply() == shares, "Unexpected total supply");
        require(vault.totalAssets() == seedDeposit, "Unexpected total assets");

        console2.log("  Verification passed!");

        // Verification info
        console2.log("");
        console2.log("Verification command:");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(vault)),
                " src/SplUSDv2.sol:SplUSDv2 ",
                "--constructor-args $(cast abi-encode \"constructor(address)\" ",
                vm.toString(plUSD),
                ")"
            )
        );

        return vault;
    }
}
