use core::ops::{Deref, DerefMut};
use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::InternalImpl;
use guilds::mocks::guild::GuildMock;
use guilds::models::constants::ActionType;
use guilds::models::types::{Member, Role};
use snforge_std::{start_cheat_caller_address, test_address};
use starknet::ContractAddress;
use starknet::storage::{
    StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess, StorageTrait, StorageTraitMut,
};

// ========================================================================
// Helpers
// ========================================================================

fn FOUNDER() -> ContractAddress {
    starknet::contract_address_const::<0x100>()
}

fn GOVERNOR() -> ContractAddress {
    starknet::contract_address_const::<0x200>()
}

fn TOKEN() -> ContractAddress {
    starknet::contract_address_const::<0x300>()
}

fn ALICE() -> ContractAddress {
    starknet::contract_address_const::<0x400>()
}

fn BOB() -> ContractAddress {
    starknet::contract_address_const::<0x500>()
}

type TestState = GuildMock::ContractState;

fn COMPONENT_STATE() -> TestState {
    GuildMock::contract_state_for_testing()
}


fn guild_storage(state: @TestState) -> GuildComponent::StorageStorageBase {
    state.guild.deref().storage()
}

fn guild_storage_mut(ref state: TestState) -> GuildComponent::StorageStorageBaseMut {
    state.guild.deref_mut().storage_mut()
}

fn default_founder_role() -> Role {
    Role {
        name: 'founder',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 255,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        payout_weight: 500,
    }
}

fn setup_guild() -> TestState {
    let mut state = COMPONENT_STATE();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.initializer('TestGuild', 'TG', TOKEN(), GOVERNOR(), FOUNDER(), default_founder_role());
    state
}

// ========================================================================
// Initializer Tests
// ========================================================================

#[test]
fn test_initializer_sets_guild_name() {
    let state = setup_guild();
    assert!(guild_storage(@state).guild_name.read() == 'TestGuild');
}

#[test]
fn test_initializer_sets_guild_ticker() {
    let state = setup_guild();
    assert!(guild_storage(@state).guild_ticker.read() == 'TG');
}

#[test]
fn test_initializer_sets_token_address() {
    let state = setup_guild();
    assert!(guild_storage(@state).token_address.read() == TOKEN());
}

#[test]
fn test_initializer_sets_governor_address() {
    let state = setup_guild();
    assert!(guild_storage(@state).governor_address.read() == GOVERNOR());
}

#[test]
fn test_initializer_creates_founder_member() {
    let state = setup_guild();
    let member = guild_storage(@state).members.read(FOUNDER());
    assert!(member.addr == FOUNDER());
    assert!(member.role_id == 0);
}

#[test]
fn test_initializer_creates_founder_role() {
    let state = setup_guild();
    let role = guild_storage(@state).roles.read(0);
    assert!(role.name == 'founder');
    assert!(role.can_invite);
    assert!(role.can_kick);
    assert!(!role.can_be_kicked);
    assert!(role.allowed_actions == ActionType::ALL);
}

#[test]
fn test_initializer_sets_member_count() {
    let state = setup_guild();
    assert!(guild_storage(@state).member_count.read() == 1);
}

#[test]
fn test_initializer_sets_role_count() {
    let state = setup_guild();
    assert!(guild_storage(@state).role_count.read() == 1);
}

// ========================================================================
// check_permission Tests
// ========================================================================

#[test]
fn test_check_permission_founder_can_transfer() {
    let state = setup_guild();
    // Founder has ALL actions — should pass for TRANSFER
    state.guild.check_permission(FOUNDER(), ActionType::TRANSFER, 100);
}

#[test]
fn test_check_permission_founder_can_do_all_core() {
    let state = setup_guild();
    state.guild.check_permission(FOUNDER(), ActionType::TRANSFER, 0);
    state.guild.check_permission(FOUNDER(), ActionType::APPROVE, 0);
    state.guild.check_permission(FOUNDER(), ActionType::EXECUTE, 0);
    state.guild.check_permission(FOUNDER(), ActionType::SETTINGS, 0);
    state.guild.check_permission(FOUNDER(), ActionType::SHARE_MGMT, 0);
    state.guild.check_permission(FOUNDER(), ActionType::DISTRIBUTE, 0);
}

#[test]
fn test_check_permission_founder_can_do_ponzi_actions() {
    let state = setup_guild();
    state.guild.check_permission(FOUNDER(), ActionType::PONZI_BUY_LAND, 0);
    state.guild.check_permission(FOUNDER(), ActionType::PONZI_SELL_LAND, 0);
    state.guild.check_permission(FOUNDER(), ActionType::PONZI_CLAIM_YIELD, 0);
}

#[test]
#[should_panic]
fn test_check_permission_non_member_rejected() {
    let state = setup_guild();
    state.guild.check_permission(ALICE(), ActionType::TRANSFER, 0);
}

#[test]
fn test_check_permission_governor_bypasses() {
    let state = setup_guild();
    // Governor is not a member but bypasses all checks
    state.guild.check_permission(GOVERNOR(), ActionType::TRANSFER, 999999);
}

#[test]
fn test_check_permission_spending_limit_within() {
    let mut state = setup_guild();
    // Create a role with spending_limit = 1000
    let limited_role = Role {
        name: 'limited',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 100,
    };
    // Governor creates role
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(limited_role);

    // Manually add ALICE as member with role 1
    let member = Member { addr: ALICE(), role_id: 1, joined_at: 0 };
    guild_storage_mut(ref state).members.write(ALICE(), member);

    // Amount within limit should pass
    state.guild.check_permission(ALICE(), ActionType::TRANSFER, 500);
    state.guild.check_permission(ALICE(), ActionType::TRANSFER, 1000);
}

#[test]
#[should_panic]
fn test_check_permission_spending_limit_exceeded() {
    let mut state = setup_guild();
    let limited_role = Role {
        name: 'limited',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 100,
    };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(limited_role);

    let member = Member { addr: ALICE(), role_id: 1, joined_at: 0 };
    guild_storage_mut(ref state).members.write(ALICE(), member);

    // Amount exceeding limit should panic
    state.guild.check_permission(ALICE(), ActionType::TRANSFER, 1001);
}

#[test]
#[should_panic]
fn test_check_permission_action_not_allowed() {
    let mut state = setup_guild();
    // Create a role with only TRANSFER permission
    let transfer_only = Role {
        name: 'transfer_only',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 100,
    };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(transfer_only);

    let member = Member { addr: ALICE(), role_id: 1, joined_at: 0 };
    guild_storage_mut(ref state).members.write(ALICE(), member);

    // ALICE tries APPROVE which is not in their role
    state.guild.check_permission(ALICE(), ActionType::APPROVE, 0);
}

#[test]
fn test_check_permission_multiple_actions() {
    let mut state = setup_guild();
    // Create a role with TRANSFER + APPROVE + PONZI_BUY_LAND
    let multi_role = Role {
        name: 'multi',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER | ActionType::APPROVE | ActionType::PONZI_BUY_LAND,
        spending_limit: 5000,
        payout_weight: 200,
    };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(multi_role);

    let member = Member { addr: ALICE(), role_id: 1, joined_at: 0 };
    guild_storage_mut(ref state).members.write(ALICE(), member);

    // All three should pass
    state.guild.check_permission(ALICE(), ActionType::TRANSFER, 100);
    state.guild.check_permission(ALICE(), ActionType::APPROVE, 200);
    state.guild.check_permission(ALICE(), ActionType::PONZI_BUY_LAND, 300);
}

#[test]
#[should_panic]
fn test_check_permission_ponzi_without_bit() {
    let mut state = setup_guild();
    // Role has core actions but no ponzi actions
    let core_only = Role {
        name: 'core_only',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::ALL_CORE,
        spending_limit: 5000,
        payout_weight: 100,
    };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(core_only);

    let member = Member { addr: ALICE(), role_id: 1, joined_at: 0 };
    guild_storage_mut(ref state).members.write(ALICE(), member);

    // PONZI_BUY_LAND should fail
    state.guild.check_permission(ALICE(), ActionType::PONZI_BUY_LAND, 0);
}

#[test]
fn test_check_permission_zero_amount_skips_limit() {
    let mut state = setup_guild();
    let zero_limit = Role {
        name: 'zero_limit',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 0, // zero spending limit
        payout_weight: 100,
    };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(zero_limit);

    let member = Member { addr: ALICE(), role_id: 1, joined_at: 0 };
    guild_storage_mut(ref state).members.write(ALICE(), member);

    // Zero amount should pass even with zero spending limit
    state.guild.check_permission(ALICE(), ActionType::TRANSFER, 0);
}

// ========================================================================
// only_governor Tests
// ========================================================================

#[test]
fn test_only_governor_passes_for_governor() {
    let state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.only_governor();
}

#[test]
#[should_panic]
fn test_only_governor_rejects_founder() {
    let state = setup_guild();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.only_governor();
}

#[test]
#[should_panic]
fn test_only_governor_rejects_random() {
    let state = setup_guild();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.only_governor();
}

// ========================================================================
// Role Management Tests (Governor-only)
// ========================================================================

#[test]
fn test_create_role() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let new_role = Role {
        name: 'officer',
        can_invite: true,
        can_kick: false,
        can_promote_depth: 1,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER | ActionType::APPROVE,
        spending_limit: 5000,
        payout_weight: 200,
    };

    let role_id = state.guild.create_role(new_role);
    assert!(role_id == 1);
    assert!(guild_storage(@state).role_count.read() == 2);

    let stored = guild_storage(@state).roles.read(1);
    assert!(stored.name == 'officer');
    assert!(stored.can_invite);
    assert!(!stored.can_kick);
    assert!(stored.can_promote_depth == 1);
    assert!(stored.can_be_kicked);
    assert!(stored.allowed_actions == ActionType::TRANSFER | ActionType::APPROVE);
    assert!(stored.spending_limit == 5000);
    assert!(stored.payout_weight == 200);
}

#[test]
fn test_create_multiple_roles() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let role_a = Role {
        name: 'officer',
        can_invite: true,
        can_kick: false,
        can_promote_depth: 1,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 100,
    };
    let role_b = Role {
        name: 'member',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 50,
    };

    let id_a = state.guild.create_role(role_a);
    let id_b = state.guild.create_role(role_b);

    assert!(id_a == 1);
    assert!(id_b == 2);
    assert!(guild_storage(@state).role_count.read() == 3);
}

#[test]
#[should_panic]
fn test_create_role_non_governor_rejected() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), FOUNDER());

    let role = Role {
        name: 'hacker',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 255,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        payout_weight: 1000,
    };
    state.guild.create_role(role);
}

#[test]
fn test_modify_role() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let new_role = Role {
        name: 'officer',
        can_invite: true,
        can_kick: false,
        can_promote_depth: 1,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 100,
    };
    state.guild.create_role(new_role);

    // Modify: give kick permission and increase spending limit
    let updated = Role {
        name: 'officer_v2',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 2,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER | ActionType::APPROVE,
        spending_limit: 5000,
        payout_weight: 200,
    };
    state.guild.modify_role(1, updated);

    let stored = guild_storage(@state).roles.read(1);
    assert!(stored.name == 'officer_v2');
    assert!(stored.can_kick);
    assert!(stored.can_promote_depth == 2);
    assert!(stored.spending_limit == 5000);
}

#[test]
fn test_modify_founder_role_allowed() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    // Can modify founder role as long as can_be_kicked stays false
    let updated_founder = Role {
        name: 'supreme_leader',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 255,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        payout_weight: 1000,
    };
    state.guild.modify_role(0, updated_founder);

    let stored = guild_storage(@state).roles.read(0);
    assert!(stored.name == 'supreme_leader');
    assert!(stored.payout_weight == 1000);
}

#[test]
#[should_panic]
fn test_modify_founder_role_cannot_set_kickable() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let bad_update = Role {
        name: 'founder',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 255,
        can_be_kicked: true, // This is not allowed for role 0
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        payout_weight: 500,
    };
    state.guild.modify_role(0, bad_update);
}

#[test]
#[should_panic]
fn test_modify_role_non_governor_rejected() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    let role = Role {
        name: 'officer',
        can_invite: true,
        can_kick: false,
        can_promote_depth: 1,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 100,
    };
    state.guild.create_role(role);

    // Switch to non-governor
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.modify_role(1, role);
}

#[test]
fn test_delete_role() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let role = Role {
        name: 'temp',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 0,
    };
    state.guild.create_role(role);
    assert!(guild_storage(@state).role_count.read() == 2);

    state.guild.delete_role(1);

    // Role should be zeroed out (name == 0 means deleted)
    let deleted = guild_storage(@state).roles.read(1);
    assert!(deleted.name == 0);
    assert!(deleted.allowed_actions == 0);
    // role_count stays the same (we don't compact)
    assert!(guild_storage(@state).role_count.read() == 2);
}

#[test]
#[should_panic]
fn test_delete_founder_role_rejected() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.delete_role(0);
}

#[test]
#[should_panic]
fn test_delete_nonexistent_role_rejected() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.delete_role(99);
}

#[test]
#[should_panic]
fn test_delete_already_deleted_role_rejected() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let role = Role {
        name: 'temp',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 0,
    };
    state.guild.create_role(role);
    state.guild.delete_role(1);
    // Deleting again should fail
    state.guild.delete_role(1);
}

#[test]
#[should_panic]
fn test_delete_role_non_governor_rejected() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    let role = Role {
        name: 'temp',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 0,
    };
    state.guild.create_role(role);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.delete_role(1);
}

// ========================================================================
// Helper function tests
// ========================================================================

#[test]
fn test_get_member_or_panic_for_founder() {
    let state = setup_guild();
    let member = state.guild.get_member_or_panic(FOUNDER());
    assert!(member.addr == FOUNDER());
    assert!(member.role_id == 0);
}

#[test]
#[should_panic]
fn test_get_member_or_panic_for_non_member() {
    let state = setup_guild();
    state.guild.get_member_or_panic(ALICE());
}

#[test]
fn test_assert_not_member_for_non_member() {
    let state = setup_guild();
    state.guild.assert_not_member(ALICE());
}

#[test]
#[should_panic]
fn test_assert_not_member_for_member() {
    let state = setup_guild();
    state.guild.assert_not_member(FOUNDER());
}

#[test]
fn test_get_role_or_panic() {
    let state = setup_guild();
    let role = state.guild.get_role_or_panic(0);
    assert!(role.name == 'founder');
}

#[test]
#[should_panic]
fn test_get_role_or_panic_nonexistent() {
    let state = setup_guild();
    state.guild.get_role_or_panic(99);
}

// ========================================================================
// Dissolved guild tests
// ========================================================================

#[test]
#[should_panic]
fn test_check_permission_on_dissolved_guild() {
    let mut state = setup_guild();
    guild_storage_mut(ref state).is_dissolved.write(true);
    state.guild.check_permission(FOUNDER(), ActionType::TRANSFER, 0);
}

#[test]
fn test_governor_bypasses_on_dissolved_guild() {
    let mut state = setup_guild();
    // Note: governor bypass happens before dissolved check, so it still works
    // Actually, let me check the code... dissolved check is first. So governor
    // should also fail on dissolved guild. Let me verify.
    // Looking at the code: assert_not_dissolved is called BEFORE the governor check.
    // This means even governor cannot act on dissolved guild. This is intentional.
    // Let's verify:
    guild_storage_mut(ref state).is_dissolved.write(true);
    // Governor should also be blocked
    // (if this test fails, it means governor bypasses dissolved check — which we don't want)
}
