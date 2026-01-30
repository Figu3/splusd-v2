// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SplUSDv2 - Staked plUSD Vault
/// @author Trevee
/// @notice ERC4626 vault where users stake plUSD and earn auto-compounding yield
/// @dev Yield is injected via donateYield(), which increases the share value for all stakers.
///      IMPORTANT: Deployer must seed the vault with an initial deposit and burn shares to 0xdead
///      to protect against inflation attacks. See deployment script.
contract SplUSDv2 is ERC4626 {
    using SafeERC20 for IERC20;

    /// @notice Emitted when yield is donated to the vault
    event YieldDonated(address indexed donor, uint256 amount);

    /// @notice Initialize the splUSD v2 vault
    /// @param plUSD_ The plUSD token address (underlying asset)
    constructor(
        IERC20 plUSD_
    ) ERC4626(plUSD_) ERC20("Staked plUSD v2", "splUSD") {
        require(address(plUSD_) != address(0), "SplUSDv2: zero plUSD address");
    }

    /// @notice Donate yield to the vault, increasing share value for all stakers
    /// @dev Anyone can donate. Increases totalAssets without minting shares.
    /// @param amount Amount of plUSD to donate as yield
    function donateYield(uint256 amount) external {
        require(amount > 0, "SplUSDv2: zero amount");
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDonated(msg.sender, amount);
    }
}
