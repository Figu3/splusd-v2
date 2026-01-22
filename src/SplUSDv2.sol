// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SplUSDv2 - Staked plUSD Vault
/// @author Trevee
/// @notice ERC4626 vault where users stake plUSD and earn auto-compounding yield
/// @dev Yield is injected by admin via donateYield(), which increases the share value for all stakers.
///      The contract uses OpenZeppelin's ERC4626 implementation with virtual shares/assets offset
///      to protect against the first depositor attack (inflation attack).
contract SplUSDv2 is ERC4626, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // ============ Events ============

    /// @notice Emitted when yield is donated to the vault
    /// @param donor Address that donated the yield
    /// @param amount Amount of plUSD donated
    event YieldDonated(address indexed donor, uint256 amount);

    // ============ Constants ============

    /// @dev Offset for virtual shares/assets to protect against inflation attacks
    /// See: https://docs.openzeppelin.com/contracts/5.x/erc4626#inflation-attack
    uint256 private constant VIRTUAL_OFFSET = 1e6;

    // ============ Constructor ============

    /// @notice Initialize the splUSD v2 vault
    /// @param plUSD_ The plUSD token address (underlying asset)
    /// @param admin_ Initial admin address (will own the contract)
    constructor(
        IERC20 plUSD_,
        address admin_
    ) ERC4626(plUSD_) ERC20("Staked plUSD v2", "splUSD") Ownable(admin_) {
        require(address(plUSD_) != address(0), "SplUSDv2: zero plUSD address");
        // Note: Ownable already reverts with OwnableInvalidOwner(address(0)) for zero admin
    }

    // ============ Admin Functions ============

    /// @notice Donate yield to the vault, increasing share value for all stakers
    /// @dev Anyone can donate yield, not just admin. This increases totalAssets without
    ///      minting new shares, effectively increasing the value of each existing share.
    /// @param amount Amount of plUSD to donate as yield
    function donateYield(uint256 amount) external {
        require(amount > 0, "SplUSDv2: zero amount");
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);
        emit YieldDonated(msg.sender, amount);
    }

    /// @notice Pause all deposits and withdrawals
    /// @dev Only callable by owner. Use in case of emergency (exploit, bug, etc.)
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resume normal operations after pause
    /// @dev Only callable by owner
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ ERC4626 Overrides (Pausable) ============

    /// @inheritdoc ERC4626
    /// @dev Paused when contract is paused
    function deposit(
        uint256 assets,
        address receiver
    ) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626
    /// @dev Paused when contract is paused
    function mint(
        uint256 shares,
        address receiver
    ) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626
    /// @dev Paused when contract is paused
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public override whenNotPaused returns (uint256) {
        return super.withdraw(assets, receiver, owner_);
    }

    /// @inheritdoc ERC4626
    /// @dev Paused when contract is paused
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public override whenNotPaused returns (uint256) {
        return super.redeem(shares, receiver, owner_);
    }

    // ============ ERC4626 View Overrides (Pausable + Virtual Offset) ============

    /// @inheritdoc ERC4626
    /// @dev Returns 0 when paused, otherwise unlimited
    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /// @inheritdoc ERC4626
    /// @dev Returns 0 when paused, otherwise unlimited
    function maxMint(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    /// @inheritdoc ERC4626
    /// @dev Returns 0 when paused, otherwise the owner's max withdrawable assets
    function maxWithdraw(address owner_) public view override returns (uint256) {
        return paused() ? 0 : super.maxWithdraw(owner_);
    }

    /// @inheritdoc ERC4626
    /// @dev Returns 0 when paused, otherwise the owner's max redeemable shares
    function maxRedeem(address owner_) public view override returns (uint256) {
        return paused() ? 0 : super.maxRedeem(owner_);
    }

    // ============ Virtual Offset Overrides (Inflation Attack Protection) ============

    /// @dev Override to add virtual offset for inflation attack protection
    /// @return Total assets including virtual offset
    function _decimalsOffset() internal pure override returns (uint8) {
        // Using 6 decimal offset (1e6) to match the VIRTUAL_OFFSET constant
        // This provides protection against inflation attacks while maintaining precision
        return 6;
    }
}
