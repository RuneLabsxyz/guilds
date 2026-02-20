use core::num::traits::Zero;
use core::ops::{Deref, DerefMut};
use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::InternalImpl;
use guilds::mocks::guild::GuildMock;
use guilds::models::constants::ActionType;
use guilds::models::types::{Member, PendingInvite, Role};
use snforge_std::{start_cheat_block_timestamp, start_cheat_caller_address, test_address};
use starknet::ContractAddress;
use starknet::storage::{
    StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess, StorageTrait, StorageTraitMut,
};

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

fn CHARLIE() -> ContractAddress {
    starknet::contract_address_const::<0x600>()
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

fn officer_role() -> Role {
    Role {
        name: 'officer',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 1,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 1000,
        payout_weight: 200,
    }
}

fn member_role() -> Role {
    Role {
        name: 'member',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 100,
    }
}

fn protected_role() -> Role {
    Role {
        name: 'protected',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: false,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 100,
    }
}

fn weak_inviter_role() -> Role {
    Role {
        name: 'weak_inviter',
        can_invite: true,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 50,
    }
}

fn weak_kicker_role() -> Role {
    Role {
        name: 'weak_kicker',
        can_invite: false,
        can_kick: true,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 50,
    }
}

fn setup_guild() -> TestState {
    let mut state = COMPONENT_STATE();
    start_cheat_caller_address(test_address(), FOUNDER());
    state
        .guild
        .initializer('TestGuild', 'TG', TOKEN(), GOVERNOR(), FOUNDER(), default_founder_role());
    state
}

fn setup_guild_with_roles() -> TestState {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(officer_role()); // role 1
    state.guild.create_role(member_role()); // role 2
    state.guild.create_role(protected_role()); // role 3
    state
}

fn add_member(ref state: TestState, addr: ContractAddress, role_id: u8) {
    guild_storage_mut(ref state).members.write(addr, Member { addr, role_id, joined_at: 0 });
    guild_storage_mut(ref state).member_count.write(guild_storage(@state).member_count.read() + 1);
    if role_id == 0 {
        guild_storage_mut(ref state)
            .founder_count
            .write(guild_storage(@state).founder_count.read() + 1);
    }
}

#[test]
fn test_invite_member_founder_can_invite_to_role_1() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());

    state.guild.invite_member(ALICE(), 1, 0);

    let invite = guild_storage(@state).pending_invites.read(ALICE());
    assert!(invite.role_id == 1);
    assert!(invite.invited_by == FOUNDER());
}

#[test]
#[should_panic]
fn test_invite_member_non_member_cannot_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.invite_member(BOB(), 2, 0);
}

#[test]
#[should_panic]
fn test_invite_member_rejects_zero_target_address() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(starknet::contract_address_const::<0>(), 2, 0);
}

#[test]
#[should_panic]
fn test_invite_member_member_without_can_invite_cannot_invite() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.invite_member(BOB(), 2, 0);
}

#[test]
#[should_panic]
fn test_invite_member_cannot_invite_existing_member() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);
}

#[test]
#[should_panic]
fn test_invite_member_cannot_invite_to_higher_rank() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(weak_inviter_role()); // role 4
    add_member(ref state, ALICE(), 4);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.invite_member(BOB(), 1, 0);
}

#[test]
#[should_panic]
fn test_invite_member_cannot_invite_to_equal_rank() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.invite_member(BOB(), 1, 0);
}

#[test]
#[should_panic]
fn test_invite_member_cannot_invite_to_nonexistent_role() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 99, 0);
}

#[test]
#[should_panic]
fn test_invite_member_cannot_invite_when_pending_exists() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);
    state.guild.invite_member(ALICE(), 1, 0);
}

#[test]
fn test_invite_member_governor_can_invite_to_any_role() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.invite_member(ALICE(), 0, 7777);

    let invite = guild_storage(@state).pending_invites.read(ALICE());
    assert!(invite.role_id == 0);
    assert!(invite.invited_by == GOVERNOR());
}

#[test]
#[should_panic]
fn test_invite_member_governor_cannot_invite_existing_member() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.invite_member(ALICE(), 1, 0);
}

#[test]
#[should_panic]
fn test_invite_member_governor_cannot_invite_to_nonexistent_role() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.invite_member(ALICE(), 99, 0);
}

#[test]
fn test_invite_member_with_expiry_sets_pending_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_block_timestamp(test_address(), 100);
    start_cheat_caller_address(test_address(), FOUNDER());

    state.guild.invite_member(BOB(), 1, 555);

    let invite = guild_storage(@state).pending_invites.read(BOB());
    assert!(invite.role_id == 1);
    assert!(invite.invited_by == FOUNDER());
    assert!(invite.invited_at == 100);
    assert!(invite.expires_at == 555);
}

#[test]
#[should_panic]
fn test_invite_member_rejects_expiry_in_past() {
    let mut state = setup_guild_with_roles();
    start_cheat_block_timestamp(test_address(), 100);
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(BOB(), 1, 100);
}

#[test]
fn test_invite_member_allows_replacing_expired_pending_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_block_timestamp(test_address(), 10);
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 20);

    start_cheat_block_timestamp(test_address(), 30);
    state.guild.invite_member(ALICE(), 1, 60);

    let invite = guild_storage(@state).pending_invites.read(ALICE());
    assert!(invite.role_id == 1);
    assert!(invite.invited_by == FOUNDER());
    assert!(invite.invited_at == 30);
    assert!(invite.expires_at == 60);
}

#[test]
fn test_accept_invite_valid_invite_creates_member() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.addr == ALICE());
    assert!(member.role_id == 2);
}

#[test]
fn test_accept_invite_clears_pending_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();

    let invite = guild_storage(@state).pending_invites.read(ALICE());
    assert!(invite.role_id == 0);
    assert!(invite.invited_by == Zero::zero());
    assert!(invite.invited_at == 0);
    assert!(invite.expires_at == 0);
}

#[test]
fn test_accept_invite_increments_member_count() {
    let mut state = setup_guild_with_roles();
    assert!(guild_storage(@state).member_count.read() == 1);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();

    assert!(guild_storage(@state).member_count.read() == 2);
}

#[test]
#[should_panic]
fn test_accept_invite_existing_member_cannot_accept_seeded_invite() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);

    guild_storage_mut(ref state)
        .pending_invites
        .write(
            ALICE(),
            PendingInvite { role_id: 1, invited_by: FOUNDER(), invited_at: 10, expires_at: 0 },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();
}

#[test]
#[should_panic]
fn test_accept_invite_no_pending_invite_fails() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();
}

#[test]
#[should_panic]
fn test_accept_invite_expired_invite_fails() {
    let mut state = setup_guild_with_roles();
    start_cheat_block_timestamp(test_address(), 10);
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 20);

    start_cheat_block_timestamp(test_address(), 20);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();
}

#[test]
fn test_accept_invite_zero_expiry_is_always_valid() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);

    start_cheat_block_timestamp(test_address(), 999999);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.addr == ALICE());
}

#[test]
fn test_accept_invite_to_role_zero_increments_founder_count() {
    let mut state = setup_guild_with_roles();
    assert!(guild_storage(@state).founder_count.read() == 1);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.invite_member(ALICE(), 0, 0);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.accept_invite();

    assert!(guild_storage(@state).founder_count.read() == 2);
}

#[test]
fn test_kick_member_founder_can_kick_lower_rank_kickable_member() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    assert!(guild_storage(@state).member_count.read() == 2);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.kick_member(ALICE());

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.addr == Zero::zero());
    assert!(guild_storage(@state).member_count.read() == 1);
}

#[test]
#[should_panic]
fn test_kick_member_cannot_kick_self() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.kick_member(FOUNDER());
}

#[test]
#[should_panic]
fn test_kick_member_cannot_kick_higher_rank() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(weak_kicker_role()); // role 4
    add_member(ref state, ALICE(), 4);
    add_member(ref state, BOB(), 1);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.kick_member(BOB());
}

#[test]
#[should_panic]
fn test_kick_member_cannot_kick_equal_rank() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    add_member(ref state, BOB(), 1);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.kick_member(BOB());
}

#[test]
#[should_panic]
fn test_kick_member_cannot_kick_non_kickable_member() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 3);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.kick_member(ALICE());
}

#[test]
#[should_panic]
fn test_kick_member_cannot_kick_non_member() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.kick_member(ALICE());
}

#[test]
#[should_panic]
fn test_kick_member_rejects_zero_target_address() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.kick_member(starknet::contract_address_const::<0>());
}

#[test]
#[should_panic]
fn test_kick_member_member_without_can_kick_cannot_kick() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    add_member(ref state, BOB(), 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.kick_member(BOB());
}

#[test]
fn test_kick_member_governor_can_kick_anyone_including_non_kickable() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 3);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.kick_member(ALICE());

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.addr == Zero::zero());
}

#[test]
fn test_kick_member_decrements_member_count() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    assert!(guild_storage(@state).member_count.read() == 2);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.kick_member(ALICE());

    assert!(guild_storage(@state).member_count.read() == 1);
}

#[test]
fn test_kick_member_kick_founder_decrements_founder_count() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 0);
    assert!(guild_storage(@state).founder_count.read() == 2);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.kick_member(ALICE());

    assert!(guild_storage(@state).founder_count.read() == 1);
}

#[test]
fn test_leave_guild_member_can_leave() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.leave_guild();

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.addr == Zero::zero());
}

#[test]
fn test_leave_guild_founder_can_leave_if_other_founders_exist() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 0);
    assert!(guild_storage(@state).founder_count.read() == 2);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.leave_guild();

    assert!(guild_storage(@state).founder_count.read() == 1);
    let member = guild_storage(@state).members.read(FOUNDER());
    assert!(member.addr == Zero::zero());
}

#[test]
#[should_panic]
fn test_leave_guild_last_founder_cannot_leave() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.leave_guild();
}

#[test]
fn test_leave_guild_decrements_member_count() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    assert!(guild_storage(@state).member_count.read() == 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.leave_guild();

    assert!(guild_storage(@state).member_count.read() == 1);
}

#[test]
#[should_panic]
fn test_leave_guild_non_member_cannot_leave() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.leave_guild();
}

#[test]
fn test_change_member_role_founder_can_promote_member_within_depth() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.change_member_role(ALICE(), 1);

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.role_id == 1);
}

#[test]
fn test_change_member_role_officer_can_change_lower_rank_member_within_depth() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    add_member(ref state, BOB(), 3);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(BOB(), 2);

    let member = guild_storage(@state).members.read(BOB());
    assert!(member.role_id == 2);
}

#[test]
#[should_panic]
fn test_change_member_role_cannot_modify_equal_rank_member() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    add_member(ref state, BOB(), 1);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(BOB(), 2);
}

#[test]
#[should_panic]
fn test_change_member_role_cannot_modify_higher_rank_member() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(FOUNDER(), 2);
}

#[test]
#[should_panic]
fn test_change_member_role_rejects_zero_target_address() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.change_member_role(starknet::contract_address_const::<0>(), 1);
}

#[test]
#[should_panic]
fn test_change_member_role_cannot_promote_to_equal_rank() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    add_member(ref state, BOB(), 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(BOB(), 1);
}

#[test]
#[should_panic]
fn test_change_member_role_cannot_promote_to_higher_rank() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    add_member(ref state, BOB(), 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(BOB(), 0);
}

#[test]
#[should_panic]
fn test_change_member_role_cannot_promote_beyond_depth() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 1);
    add_member(ref state, BOB(), 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(BOB(), 3);
}

#[test]
#[should_panic]
fn test_change_member_role_member_without_permission_cannot_promote() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    add_member(ref state, BOB(), 2);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.change_member_role(BOB(), 3);
}

#[test]
fn test_change_member_role_governor_can_change_any_member_role() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 3);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.change_member_role(ALICE(), 0);

    let member = guild_storage(@state).members.read(ALICE());
    assert!(member.role_id == 0);
}

#[test]
#[should_panic]
fn test_change_member_role_cannot_demote_last_founder() {
    let mut state = setup_guild_with_roles();

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.change_member_role(FOUNDER(), 2);
}

#[test]
fn test_change_member_role_from_or_to_role_zero_updates_founder_count() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, ALICE(), 2);
    assert!(guild_storage(@state).founder_count.read() == 1);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.change_member_role(ALICE(), 0);
    assert!(guild_storage(@state).founder_count.read() == 2);

    state.guild.change_member_role(ALICE(), 2);
    assert!(guild_storage(@state).founder_count.read() == 1);
}

#[test]
fn test_revoke_invite_inviter_can_revoke_their_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);
    state.guild.revoke_invite(ALICE());

    let invite = guild_storage(@state).pending_invites.read(ALICE());
    assert!(invite.invited_by == Zero::zero());
}

#[test]
#[should_panic]
fn test_revoke_invite_other_member_cannot_revoke_invite_they_did_not_send() {
    let mut state = setup_guild_with_roles();
    add_member(ref state, BOB(), 1);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);

    start_cheat_caller_address(test_address(), BOB());
    state.guild.revoke_invite(ALICE());
}

#[test]
fn test_revoke_invite_governor_can_revoke_any_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(ALICE(), 2, 0);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.revoke_invite(ALICE());

    let invite = guild_storage(@state).pending_invites.read(ALICE());
    assert!(invite.invited_by == Zero::zero());
}

#[test]
#[should_panic]
fn test_revoke_invite_non_existent_invite_fails() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.revoke_invite(ALICE());
}

#[test]
#[should_panic]
fn test_revoke_invite_rejects_zero_target_address() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.revoke_invite(starknet::contract_address_const::<0>());
}

#[test]
fn test_revoke_invite_clears_pending_invite() {
    let mut state = setup_guild_with_roles();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.invite_member(CHARLIE(), 1, 999);
    state.guild.revoke_invite(CHARLIE());

    let invite = guild_storage(@state).pending_invites.read(CHARLIE());
    assert!(
        invite == PendingInvite {
            role_id: 0, invited_by: Zero::zero(), invited_at: 0, expires_at: 0,
        },
    );
}
