// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ISplUSDv2 - Interface for the Staked plUSD v2 Vault
/// @notice Extends ERC4626 with yield donation and pausability
interface ISplUSDv2 is IERC4626 {
    // ============ Events ============

    /// @notice Emitted when yield is donated to the vault
    /// @param donor Address that donated the yield
    /// @param amount Amount of plUSD donated
    event YieldDonated(address indexed donor, uint256 amount);

    // ============ Functions ============

    /// @notice Donate yield to the vault, increasing share value for all stakers
    /// @param amount Amount of plUSD to donate as yield
    function donateYield(uint256 amount) external;

    /// @notice Pause all deposits and withdrawals
    function pause() external;

    /// @notice Resume normal operations after pause
    function unpause() external;

    /// @notice Check if the contract is paused
    /// @return True if paused, false otherwise
    function paused() external view returns (bool);
}
