// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ISplUSDv2 - Interface for the Staked plUSD v2 Vault
/// @notice Extends ERC4626 with yield donation capability
interface ISplUSDv2 is IERC4626 {
    /// @notice Emitted when yield is donated to the vault
    event YieldDonated(address indexed donor, uint256 amount);

    /// @notice Donate yield to the vault, increasing share value for all stakers
    /// @param amount Amount of plUSD to donate as yield
    function donateYield(uint256 amount) external;
}
