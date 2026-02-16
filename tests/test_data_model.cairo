use core::num::traits::Zero;
use guilds::models::constants::{
    ActionType, BPS_DENOMINATOR, DEFAULT_PLAYER_BPS, DEFAULT_SHAREHOLDER_BPS, DEFAULT_TREASURY_BPS,
};
use guilds::models::types::{
    DistributionPolicy, EpochSnapshot, GovernorConfig, GuildRegistryEntry, InactivityFlag, Member,
    PendingInvite, PluginConfig, RedemptionWindow, Role, ShareOffer,
};
use starknet::ContractAddress;

fn ADDR_1() -> ContractAddress {
    starknet::contract_address_const::<0x1>()
}

fn ADDR_2() -> ContractAddress {
    starknet::contract_address_const::<0x2>()
}

// ========================================================================
// Struct construction tests
// ========================================================================

#[test]
fn test_role_construction() {
    let role = Role {
        name: 'admin',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 2,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL_CORE,
        spending_limit: 1000,
        payout_weight: 250,
    };
    assert!(role.name == 'admin');
    assert!(role.can_invite);
    assert!(role.can_kick);
    assert!(role.can_promote_depth == 2);
    assert!(!role.can_be_kicked);
    assert!(role.allowed_actions == ActionType::ALL_CORE);
    assert!(role.spending_limit == 1000);
    assert!(role.payout_weight == 250);
}

#[test]
fn test_member_construction() {
    let member = Member { addr: ADDR_1(), role_id: 0, joined_at: 1000 };
    assert!(member.addr == ADDR_1());
    assert!(member.role_id == 0);
    assert!(member.joined_at == 1000);
}

#[test]
fn test_pending_invite_construction() {
    let invite = PendingInvite {
        role_id: 1, invited_by: ADDR_1(), invited_at: 1000, expires_at: 2000,
    };
    assert!(invite.role_id == 1);
    assert!(invite.invited_by == ADDR_1());
    assert!(invite.invited_at == 1000);
    assert!(invite.expires_at == 2000);
}

#[test]
fn test_plugin_config_construction() {
    let plugin = PluginConfig {
        target_contract: ADDR_1(), enabled: true, action_offset: 8, action_count: 6,
    };
    assert!(plugin.target_contract == ADDR_1());
    assert!(plugin.enabled);
    assert!(plugin.action_offset == 8);
    assert!(plugin.action_count == 6);
}

#[test]
fn test_distribution_policy_construction() {
    let policy = DistributionPolicy {
        treasury_bps: DEFAULT_TREASURY_BPS,
        player_bps: DEFAULT_PLAYER_BPS,
        shareholder_bps: DEFAULT_SHAREHOLDER_BPS,
    };
    assert!(policy.treasury_bps == 3000);
    assert!(policy.player_bps == 5000);
    assert!(policy.shareholder_bps == 2000);
    // Must sum to 10000
    let total: u16 = policy.treasury_bps + policy.player_bps + policy.shareholder_bps;
    assert!(total == BPS_DENOMINATOR);
}

#[test]
fn test_share_offer_construction() {
    let offer = ShareOffer {
        deposit_token: ADDR_1(),
        max_total: 10000,
        minted_so_far: 0,
        price_per_share: 100,
        expires_at: 5000,
    };
    assert!(offer.deposit_token == ADDR_1());
    assert!(offer.max_total == 10000);
    assert!(offer.minted_so_far == 0);
    assert!(offer.price_per_share == 100);
    assert!(offer.expires_at == 5000);
}

#[test]
fn test_redemption_window_construction() {
    let window = RedemptionWindow {
        enabled: true, max_per_epoch: 500, redeemed_this_epoch: 0, cooldown_epochs: 3,
    };
    assert!(window.enabled);
    assert!(window.max_per_epoch == 500);
    assert!(window.redeemed_this_epoch == 0);
    assert!(window.cooldown_epochs == 3);
}

#[test]
fn test_inactivity_flag_construction() {
    let flag = InactivityFlag { flagged_at: 1000, flagged_by: ADDR_1() };
    assert!(flag.flagged_at == 1000);
    assert!(flag.flagged_by == ADDR_1());
}

#[test]
fn test_epoch_snapshot_construction() {
    let snapshot = EpochSnapshot {
        total_revenue: 10000,
        treasury_amount: 3000,
        player_amount: 5000,
        shareholder_amount: 2000,
        active_supply: 1000000,
        finalized_at: 5000,
    };
    assert!(snapshot.total_revenue == 10000);
    assert!(snapshot.treasury_amount == 3000);
    assert!(snapshot.player_amount == 5000);
    assert!(snapshot.shareholder_amount == 2000);
    assert!(snapshot.active_supply == 1000000);
    assert!(snapshot.finalized_at == 5000);
    // Revenue split should sum correctly
    let sum = snapshot.treasury_amount + snapshot.player_amount + snapshot.shareholder_amount;
    assert!(sum == snapshot.total_revenue);
}

#[test]
fn test_guild_registry_entry_construction() {
    let entry = GuildRegistryEntry {
        guild_address: ADDR_1(),
        token_address: ADDR_2(),
        governor_address: ADDR_1(),
        name: 'TestGuild',
        ticker: 'TG',
        creator: ADDR_2(),
        created_at: 1000,
        is_active: true,
    };
    assert!(entry.guild_address == ADDR_1());
    assert!(entry.name == 'TestGuild');
    assert!(entry.ticker == 'TG');
    assert!(entry.is_active);
}

#[test]
fn test_governor_config_construction() {
    let config = GovernorConfig {
        voting_delay: 86400,
        voting_period: 259200,
        proposal_threshold: 10000,
        quorum_bps: 1000, // 10%
        timelock_delay: 86400,
    };
    assert!(config.voting_delay == 86400);
    assert!(config.voting_period == 259200);
    assert!(config.proposal_threshold == 10000);
    assert!(config.quorum_bps == 1000);
    assert!(config.timelock_delay == 86400);
}

// ========================================================================
// Action type bitmask tests
// ========================================================================

#[test]
fn test_action_type_bits_are_distinct() {
    // Each core action should be a distinct power of 2
    assert!(ActionType::TRANSFER == 0x1);
    assert!(ActionType::APPROVE == 0x2);
    assert!(ActionType::EXECUTE == 0x4);
    assert!(ActionType::SETTINGS == 0x8);
    assert!(ActionType::SHARE_MGMT == 0x10);
    assert!(ActionType::DISTRIBUTE == 0x20);

    // PonziLand actions start at bit 8
    assert!(ActionType::PONZI_BUY_LAND == 0x100);
    assert!(ActionType::PONZI_SELL_LAND == 0x200);
    assert!(ActionType::PONZI_SET_PRICE == 0x400);
    assert!(ActionType::PONZI_CLAIM_YIELD == 0x800);
    assert!(ActionType::PONZI_STAKE == 0x1000);
    assert!(ActionType::PONZI_UNSTAKE == 0x2000);
}

#[test]
fn test_action_type_no_overlap() {
    // Core and PonziLand action masks should not overlap
    assert!(ActionType::ALL_CORE & ActionType::ALL_PONZI == 0);
}

#[test]
fn test_action_type_all_includes_both() {
    assert!(ActionType::ALL == (ActionType::ALL_CORE | ActionType::ALL_PONZI));
}

#[test]
fn test_bitmask_permission_check() {
    // Simulate permission check: role has TRANSFER + PONZI_BUY_LAND
    let allowed = ActionType::TRANSFER | ActionType::PONZI_BUY_LAND;

    // Should pass for TRANSFER
    assert!(allowed & ActionType::TRANSFER != 0);
    // Should pass for PONZI_BUY_LAND
    assert!(allowed & ActionType::PONZI_BUY_LAND != 0);
    // Should fail for APPROVE
    assert!(allowed & ActionType::APPROVE == 0);
    // Should fail for EXECUTE
    assert!(allowed & ActionType::EXECUTE == 0);
    // Should fail for PONZI_SELL_LAND
    assert!(allowed & ActionType::PONZI_SELL_LAND == 0);
}

#[test]
fn test_role_with_all_core_permissions() {
    let role = Role {
        name: 'treasurer',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::ALL_CORE,
        spending_limit: 10000,
        payout_weight: 100,
    };

    // Should have all core actions
    assert!(role.allowed_actions & ActionType::TRANSFER != 0);
    assert!(role.allowed_actions & ActionType::APPROVE != 0);
    assert!(role.allowed_actions & ActionType::EXECUTE != 0);
    assert!(role.allowed_actions & ActionType::SETTINGS != 0);
    assert!(role.allowed_actions & ActionType::SHARE_MGMT != 0);
    assert!(role.allowed_actions & ActionType::DISTRIBUTE != 0);

    // Should NOT have PonziLand actions
    assert!(role.allowed_actions & ActionType::PONZI_BUY_LAND == 0);
    assert!(role.allowed_actions & ActionType::PONZI_SELL_LAND == 0);
}

#[test]
fn test_role_equality() {
    let role_a = Role {
        name: 'admin',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 3,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFF,
        payout_weight: 500,
    };
    let role_b = Role {
        name: 'admin',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 3,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFF,
        payout_weight: 500,
    };
    assert!(role_a == role_b);
}

// ========================================================================
// Struct equality tests
// ========================================================================

#[test]
fn test_member_equality() {
    let a = Member { addr: ADDR_1(), role_id: 1, joined_at: 100 };
    let b = Member { addr: ADDR_1(), role_id: 1, joined_at: 100 };
    assert!(a == b);
}

#[test]
fn test_distribution_policy_equality() {
    let a = DistributionPolicy { treasury_bps: 3000, player_bps: 5000, shareholder_bps: 2000 };
    let b = DistributionPolicy { treasury_bps: 3000, player_bps: 5000, shareholder_bps: 2000 };
    assert!(a == b);
}
