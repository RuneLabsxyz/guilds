/// Action type bitmask constants.
///
/// Core guild/treasury actions occupy bits 0–7.
/// Plugin actions start at bit 8 (each plugin gets a contiguous range).
///
/// Usage: a Role's `allowed_actions: u32` field is a bitwise OR of these constants.
/// Permission check: `role.allowed_actions & action_type != 0`
pub mod ActionType {
    /// Transfer ERC20 tokens from treasury
    pub const TRANSFER: u32 = 0x1; // bit 0
    /// Approve ERC20 spending from treasury
    pub const APPROVE: u32 = 0x2; // bit 1
    /// Execute arbitrary call from guild contract
    pub const EXECUTE: u32 = 0x4; // bit 2
    /// Modify guild settings (non-role, non-governance settings)
    pub const SETTINGS: u32 = 0x8; // bit 3
    /// Manage share offerings
    pub const SHARE_MGMT: u32 = 0x10; // bit 4
    /// Trigger epoch finalization and distribution
    pub const DISTRIBUTE: u32 = 0x20; // bit 5
    // bits 6-7 reserved for future core actions

    /// PonziLand plugin actions (bits 8-15)
    pub const PONZI_BUY_LAND: u32 = 0x100; // bit 8
    pub const PONZI_SELL_LAND: u32 = 0x200; // bit 9
    pub const PONZI_SET_PRICE: u32 = 0x400; // bit 10
    pub const PONZI_CLAIM_YIELD: u32 = 0x800; // bit 11
    pub const PONZI_STAKE: u32 = 0x1000; // bit 12
    pub const PONZI_UNSTAKE: u32 = 0x2000; // bit 13
    // bits 14-15 reserved for future PonziLand actions

    // bits 16-23: available for plugin slot 2
    // bits 24-31: available for plugin slot 3

    /// Convenience: all core actions
    pub const ALL_CORE: u32 = 0x3F; // bits 0-5
    /// Convenience: all PonziLand actions
    pub const ALL_PONZI: u32 = 0x3F00; // bits 8-13
    /// Convenience: all actions (core + ponziland)
    pub const ALL: u32 = 0x3F3F; // bits 0-5 + 8-13
}

/// Basis points denominator (100% = 10000 bps)
pub const BPS_DENOMINATOR: u16 = 10000;

/// Default distribution policy values
pub const DEFAULT_TREASURY_BPS: u16 = 3000; // 30%
pub const DEFAULT_PLAYER_BPS: u16 = 5000; // 50%
pub const DEFAULT_SHAREHOLDER_BPS: u16 = 2000; // 20%

/// Default inactivity threshold in seconds (90 days)
pub const DEFAULT_INACTIVITY_THRESHOLD: u64 = 7_776_000;

/// Default initial token supply (1000 tokens with 18 decimals)
pub const DEFAULT_INITIAL_SUPPLY: u256 = 1_000_000_000_000_000_000_000;

/// 10^18 token unit multiplier used for share pricing
pub const TOKEN_MULTIPLIER: u256 = 1_000_000_000_000_000_000;
