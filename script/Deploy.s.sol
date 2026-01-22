// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Script, console2 } from "forge-std/Script.sol";
import { SplUSDv2 } from "../src/SplUSDv2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Deploy Script for SplUSDv2
/// @notice Deploys the splUSD v2 vault to Plasma mainnet or testnet
contract DeployScript is Script {
    // Plasma Mainnet addresses
    address public constant PLASMA_PLUSD = 0xf91c31299E998C5127Bc5F11e4a657FC0cF358CD;

    // Deployment parameters (set via environment or override in child contracts)
    address public plUSD;
    address public admin;
    uint256 public seedDeposit;

    function setUp() public virtual {
        // Default to Plasma mainnet plUSD
        plUSD = vm.envOr("PLUSD_ADDRESS", PLASMA_PLUSD);
        admin = vm.envAddress("ADMIN_ADDRESS");
        seedDeposit = vm.envOr("SEED_DEPOSIT", uint256(1000e18));
    }

    function run() public returns (SplUSDv2 vault) {
        require(admin != address(0), "ADMIN_ADDRESS not set");
        require(plUSD != address(0), "plUSD address not set");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console2.log("Deploying SplUSDv2...");
        console2.log("  plUSD:", plUSD);
        console2.log("  Admin:", admin);
        console2.log("  Seed deposit:", seedDeposit);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy vault
        vault = new SplUSDv2(IERC20(plUSD), admin);

        console2.log("  Vault deployed at:", address(vault));

        // Seed deposit to protect against inflation attack
        if (seedDeposit > 0) {
            IERC20(plUSD).approve(address(vault), seedDeposit);
            vault.deposit(seedDeposit, admin);
            console2.log("  Seed deposit completed:", seedDeposit);
        }

        vm.stopBroadcast();

        // Verification info
        console2.log("");
        console2.log("Verification command:");
        console2.log(
            string.concat(
                "forge verify-contract ",
                vm.toString(address(vault)),
                " src/SplUSDv2.sol:SplUSDv2 ",
                "--constructor-args $(cast abi-encode \"constructor(address,address)\" ",
                vm.toString(plUSD),
                " ",
                vm.toString(admin),
                ")"
            )
        );

        return vault;
    }
}

/// @title Deploy Script for Testnet
/// @notice Deploys to testnet with mock plUSD for testing
contract DeployTestnetScript is DeployScript {
    function setUp() public override {
        // Use environment variables for testnet
        plUSD = vm.envAddress("PLUSD_ADDRESS");
        admin = vm.envAddress("ADMIN_ADDRESS");
        seedDeposit = vm.envOr("SEED_DEPOSIT", uint256(1000e18));
    }
}
