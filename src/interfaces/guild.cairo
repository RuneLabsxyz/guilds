use guilds::models::types::{
    DistributionPolicy, EpochSnapshot, Member, PendingInvite, PluginConfig, RedemptionWindow, Role,
    ShareOffer,
};
use starknet::ContractAddress;

/// Guild write operations — membership, treasury, revenue, shares, lifecycle.
#[starknet::interface]
pub trait IGuild<TState> {
    // --- Membership ---

    /// Invite a new member to the guild with a specific role and optional expiry.
    fn invite_member(ref self: TState, target: ContractAddress, role_id: u8, expires_at: u64);

    /// Accept a pending invite (caller must have been invited).
    fn accept_invite(ref self: TState);

    /// Kick a member from the guild.
    fn kick_member(ref self: TState, target: ContractAddress);

    /// Leave the guild voluntarily.
    fn leave_guild(ref self: TState);

    /// Change a member's role (promote or demote).
    fn change_member_role(ref self: TState, target: ContractAddress, new_role_id: u8);

    /// Revoke a pending invite.
    fn revoke_invite(ref self: TState, target: ContractAddress);

    // --- Role Management (Governor only) ---

    /// Create a new role. Only callable by the Governor.
    fn create_role(ref self: TState, role: Role);

    /// Modify an existing role. Only callable by the Governor.
    fn modify_role(ref self: TState, role_id: u8, role: Role);

    /// Delete a role. Only callable by the Governor. Cannot delete role 0.
    fn delete_role(ref self: TState, role_id: u8);

    // --- Treasury ---

    /// Execute a core treasury action (transfer, approve, etc.).
    fn execute_core_action(
        ref self: TState,
        action_type: u32,
        target: ContractAddress,
        token: ContractAddress,
        amount: u256,
        calldata: Span<felt252>,
    );

    /// Execute a plugin action (game-specific).
    fn execute_plugin_action(
        ref self: TState, plugin_id: felt252, action_index: u8, calldata: Span<felt252>,
    );

    // --- Plugin Management (Governor only) ---

    /// Register a new plugin. Only callable by the Governor.
    fn register_plugin(
        ref self: TState,
        plugin_id: felt252,
        target_contract: ContractAddress,
        action_offset: u8,
        action_count: u8,
    );

    /// Enable or disable a plugin. Only callable by the Governor.
    fn toggle_plugin(ref self: TState, plugin_id: felt252, enabled: bool);

    // --- Revenue ---

    /// Set the revenue distribution policy. Only callable by the Governor.
    fn set_distribution_policy(ref self: TState, policy: DistributionPolicy);

    /// Finalize the current epoch, snapshotting revenue for claims.
    fn finalize_epoch(ref self: TState);

    /// Claim player revenue for a specific epoch (based on role payout_weight).
    fn claim_player_revenue(ref self: TState, epoch: u64);

    /// Claim shareholder revenue for a specific epoch (based on token balance).
    fn claim_shareholder_revenue(ref self: TState, epoch: u64);

    // --- Shares ---

    /// Create a share offering. Only callable by the Governor.
    fn create_share_offer(ref self: TState, offer: ShareOffer);

    /// Buy shares from the active offering.
    fn buy_shares(ref self: TState, amount: u256);

    /// Configure the redemption window. Only callable by the Governor.
    fn set_redemption_window(ref self: TState, window: RedemptionWindow);

    /// Redeem (burn) shares for proportional treasury value.
    fn redeem_shares(ref self: TState, amount: u256);

    // --- Lifecycle ---

    /// Dissolve the guild. Only callable by the Governor.
    fn dissolve(ref self: TState);
}

/// Guild read-only view functions.
#[starknet::interface]
pub trait IGuildView<TState> {
    fn get_guild_name(self: @TState) -> felt252;
    fn get_guild_ticker(self: @TState) -> felt252;
    fn get_token_address(self: @TState) -> ContractAddress;
    fn get_governor_address(self: @TState) -> ContractAddress;
    fn get_member(self: @TState, addr: ContractAddress) -> Member;
    fn get_role(self: @TState, role_id: u8) -> Role;
    fn get_role_count(self: @TState) -> u8;
    fn get_member_count(self: @TState) -> u32;
    fn get_pending_invite(self: @TState, addr: ContractAddress) -> PendingInvite;
    fn get_plugin(self: @TState, plugin_id: felt252) -> PluginConfig;
    fn get_distribution_policy(self: @TState) -> DistributionPolicy;
    fn get_current_epoch(self: @TState) -> u64;
    fn get_epoch_snapshot(self: @TState, epoch: u64) -> EpochSnapshot;
    fn get_active_offer(self: @TState) -> ShareOffer;
    fn has_active_offer(self: @TState) -> bool;
    fn get_redemption_window(self: @TState) -> RedemptionWindow;
}
