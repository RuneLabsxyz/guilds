use starknet::ContractAddress;

/// A role defines a set of permissions and economic weight within the guild.
/// Roles are created/modified exclusively through governance proposals.
/// Role 0 is always the "founder" role, created at guild initialization.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Role {
    /// Human-readable name (short, stored as felt252)
    pub name: felt252,
    /// Whether members with this role can invite new members
    pub can_invite: bool,
    /// Whether members with this role can kick other members
    pub can_kick: bool,
    /// How many rank levels below this role the member can promote to.
    /// 0 = cannot promote anyone. 1 = one level below self. etc.
    pub can_promote_depth: u8,
    /// Whether members with this role can be kicked by others
    pub can_be_kicked: bool,
    /// Bitmask of allowed action types (see ActionType constants).
    /// Each bit corresponds to one action. Bit 0 = TRANSFER, etc.
    /// Plugin actions start at higher bit offsets (PonziLand at bit 8).
    pub allowed_actions: u32,
    /// Maximum amount (in base token) this role can spend per transaction.
    /// 0 = no spending allowed. u256::MAX = unlimited.
    pub spending_limit: u256,
    /// Weight for revenue distribution. Higher = larger share of player pool.
    /// Relative to sum of all role payout_weights across active members.
    pub payout_weight: u16,
}

/// A guild member.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Member {
    /// The member's wallet address
    pub addr: ContractAddress,
    /// The role_id assigned to this member (index into roles map)
    pub role_id: u8,
    /// Block timestamp when the member joined
    pub joined_at: u64,
}

/// A pending invitation that has not yet been accepted.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct PendingInvite {
    /// The role the invited address will receive upon accepting
    pub role_id: u8,
    /// Who sent the invite
    pub invited_by: ContractAddress,
    /// Block timestamp when the invite was created
    pub invited_at: u64,
    /// Block timestamp after which the invite expires (0 = never expires)
    pub expires_at: u64,
}

/// Configuration for a plugin (external game integration).
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct PluginConfig {
    /// The target contract address for this plugin (e.g. PonziLand game contract)
    pub target_contract: ContractAddress,
    /// Whether this plugin is currently enabled
    pub enabled: bool,
    /// Starting bit offset in the allowed_actions bitmask for this plugin's actions.
    /// Core actions use bits 0-7. PonziLand uses 8-15. Other games at 16+.
    pub action_offset: u8,
    /// Number of distinct actions this plugin defines
    pub action_count: u8,
}

/// Revenue distribution policy — how incoming revenue is split.
/// All values in basis points (1 bps = 0.01%). Must sum to 10000.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct DistributionPolicy {
    /// Percentage kept in treasury (retained earnings)
    pub treasury_bps: u16,
    /// Percentage distributed to active players/members (split by payout_weight)
    pub player_bps: u16,
    /// Percentage distributed to token holders (proportional to token balance)
    pub shareholder_bps: u16,
}

/// A share offering — allows the guild to sell new tokens for capital.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct ShareOffer {
    /// The ERC20 token accepted as payment (e.g. LORDS, ETH)
    pub deposit_token: ContractAddress,
    /// Maximum total tokens to mint in this offering
    pub max_total: u256,
    /// How many tokens have been minted so far in this offering
    pub minted_so_far: u256,
    /// Price per guild token, denominated in deposit_token
    pub price_per_share: u256,
    /// Block timestamp after which the offering closes (0 = no expiry)
    pub expires_at: u64,
}

/// Redemption window configuration — allows token holders to burn tokens
/// and withdraw proportional treasury share.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct RedemptionWindow {
    /// Whether redemption is currently enabled
    pub enabled: bool,
    /// Maximum tokens that can be redeemed per epoch
    pub max_per_epoch: u256,
    /// How many tokens have been redeemed in the current epoch
    pub redeemed_this_epoch: u256,
    /// Number of epochs a member must wait after redeeming before redeeming again
    pub cooldown_epochs: u32,
}

/// Tracks when a token holder was flagged for inactivity.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct InactivityFlag {
    /// Block timestamp when the holder was flagged
    pub flagged_at: u64,
    /// Who flagged them
    pub flagged_by: ContractAddress,
}

/// Snapshot of revenue for one epoch.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct EpochSnapshot {
    /// Total revenue received during this epoch
    pub total_revenue: u256,
    /// Amount allocated to treasury
    pub treasury_amount: u256,
    /// Amount allocated to player pool
    pub player_amount: u256,
    /// Amount allocated to shareholder pool
    pub shareholder_amount: u256,
    /// Total active token supply at snapshot time (for shareholder calculations)
    pub active_supply: u256,
    /// Block timestamp when this epoch was finalized
    pub finalized_at: u64,
}

/// Registry entry for a deployed guild (stored in GuildFactory).
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct GuildRegistryEntry {
    pub guild_address: ContractAddress,
    pub token_address: ContractAddress,
    pub governor_address: ContractAddress,
    pub name: felt252,
    pub ticker: felt252,
    pub creator: ContractAddress,
    pub created_at: u64,
    pub is_active: bool,
}

/// Governor configuration used during guild deployment.
/// Not stored on-chain after initialization — passed to Governor constructor.
#[derive(Drop, Serde, Copy)]
pub struct GovernorConfig {
    pub voting_delay: u64,
    pub voting_period: u64,
    pub proposal_threshold: u256,
    /// Quorum as basis points of active supply (e.g. 1000 = 10%)
    pub quorum_bps: u16,
    pub timelock_delay: u64,
}
