use starknet::ContractAddress;

// ========================================================================
// Membership Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct MemberInvited {
    #[key]
    pub target: ContractAddress,
    pub role_id: u8,
    pub invited_by: ContractAddress,
    pub expires_at: u64,
}

#[derive(Drop, starknet::Event)]
pub struct MemberJoined {
    #[key]
    pub member: ContractAddress,
    pub role_id: u8,
}

#[derive(Drop, starknet::Event)]
pub struct MemberKicked {
    #[key]
    pub member: ContractAddress,
    pub kicked_by: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct MemberLeft {
    #[key]
    pub member: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct MemberRoleChanged {
    #[key]
    pub member: ContractAddress,
    pub old_role_id: u8,
    pub new_role_id: u8,
    pub changed_by: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct InviteRevoked {
    #[key]
    pub target: ContractAddress,
    pub revoked_by: ContractAddress,
}

// ========================================================================
// Role Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct RoleCreated {
    pub role_id: u8,
    pub name: felt252,
    pub allowed_actions: u32,
    pub spending_limit: u256,
}

#[derive(Drop, starknet::Event)]
pub struct RoleModified {
    pub role_id: u8,
    pub name: felt252,
    pub allowed_actions: u32,
    pub spending_limit: u256,
}

#[derive(Drop, starknet::Event)]
pub struct RoleDeleted {
    pub role_id: u8,
}

// ========================================================================
// Treasury & Plugin Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct CoreActionExecuted {
    pub action_type: u32,
    pub target: ContractAddress,
    pub token: ContractAddress,
    pub amount: u256,
    pub executed_by: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct PluginActionExecuted {
    pub plugin_id: felt252,
    pub action_index: u8,
    pub executed_by: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct PluginRegistered {
    pub plugin_id: felt252,
    pub target_contract: ContractAddress,
    pub action_offset: u8,
    pub action_count: u8,
}

#[derive(Drop, starknet::Event)]
pub struct PluginToggled {
    pub plugin_id: felt252,
    pub enabled: bool,
}

// ========================================================================
// Revenue Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct EpochFinalized {
    pub epoch: u64,
    pub total_revenue: u256,
    pub treasury_amount: u256,
    pub player_amount: u256,
    pub shareholder_amount: u256,
}

#[derive(Drop, starknet::Event)]
pub struct PlayerRevenueClaimed {
    #[key]
    pub member: ContractAddress,
    pub epoch: u64,
    pub amount: u256,
}

#[derive(Drop, starknet::Event)]
pub struct ShareholderRevenueClaimed {
    #[key]
    pub shareholder: ContractAddress,
    pub epoch: u64,
    pub amount: u256,
}

#[derive(Drop, starknet::Event)]
pub struct DistributionPolicyChanged {
    pub treasury_bps: u16,
    pub player_bps: u16,
    pub shareholder_bps: u16,
}

// ========================================================================
// Share Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct ShareOfferCreated {
    pub deposit_token: ContractAddress,
    pub max_total: u256,
    pub price_per_share: u256,
    pub expires_at: u64,
}

#[derive(Drop, starknet::Event)]
pub struct SharesPurchased {
    #[key]
    pub buyer: ContractAddress,
    pub amount: u256,
    pub cost: u256,
}

#[derive(Drop, starknet::Event)]
pub struct SharesRedeemed {
    #[key]
    pub redeemer: ContractAddress,
    pub amount: u256,
    pub payout: u256,
}

// ========================================================================
// Inactivity Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct InactivityFlagged {
    #[key]
    pub account: ContractAddress,
    pub flagged_by: ContractAddress,
}

#[derive(Drop, starknet::Event)]
pub struct InactivityCleared {
    #[key]
    pub account: ContractAddress,
}

// ========================================================================
// Lifecycle Events
// ========================================================================

#[derive(Drop, starknet::Event)]
pub struct GuildDissolved {
    pub dissolved_at: u64,
}
