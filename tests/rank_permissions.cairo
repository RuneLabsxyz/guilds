use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::{GuildMetadataImpl, InternalImpl, Rank};
use guilds::guild::interface::IGuild;
use guilds::mocks::guild::GuildMock;
use guilds::tests::constants::{ALICE, BOB, CHARLIE, OWNER};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, test_address,
};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};


type ComponentState = GuildComponent::ComponentState<GuildMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    GuildComponent::component_state_for_testing()
}

#[test]
#[should_panic(expected: "Only owner can perform this action")]
fn test_create_rank_and_permissions() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    // Only owner can create a rank
    state.create_rank(2, true, false, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    let rank = state.ranks.read(rank_id);
    assert(rank.rank_name == 2, 'Rank name mismatch');
    assert(rank.can_invite == true, 'can_invite mismatch');
    assert(rank.can_kick == false, 'can_kick mismatch');
    assert(rank.promote == 2, 'promote mismatch');
    assert(rank.can_be_kicked == true, 'can_be_kicked mismatch');

    // Non-owner cannot create a rank
    start_cheat_caller_address(test_address(), BOB);

    state.create_rank(3, false, false, 0, false);
}

#[test]
#[should_panic(expected: "Only owner can perform this action")]
fn test_change_rank_permissions() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, false, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;

    // Change permissions as owner
    state.change_rank_permissions(rank_id, false, true, 1, false);
    let rank = state.ranks.read(rank_id);
    assert(rank.can_invite == false, 'can_invite should be false');
    assert(rank.can_kick == true, 'can_kick should be true');
    assert(rank.promote == 1, 'promote should be 1');
    assert(rank.can_be_kicked == false, 'can_be_kicked should be false');

    // Non-owner cannot change permissions
    start_cheat_caller_address(test_address(), CHARLIE);
    state.change_rank_permissions(rank_id, true, true, 2, true);
}

#[test]
#[should_panic(expected: "Cannot delete the creator's rank")]
fn test_delete_rank() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, false, 2, true);

    state.delete_rank(0);
}

#[test]
fn test_owner_can_invite_and_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a kickable rank
    state.create_rank(2, true, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB
    state.invite_member(BOB);
    // Set BOB's rank to the kickable rank
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // Owner kicks BOB
    state.kick_member(BOB);
}

#[test]
fn test_member_with_permission_can_invite_and_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a new rank with can_invite and can_kick true
    state.create_rank(2, true, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB and assigns him the new rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // BOB invites CHARLIE
    start_cheat_caller_address(test_address(), BOB);
    state.invite_member(CHARLIE);
    // Set CHARLIE's rank to the kickable rank
    let mut charlie_member = state.members.read(CHARLIE);
    charlie_member.rank_id = rank_id;
    state.members.write(CHARLIE, charlie_member);
    // BOB kicks CHARLIE
    state.kick_member(CHARLIE);
}

#[test]
#[should_panic(expected: "Caller does not have permission to invite")]
fn test_member_without_invite_permission_cannot_invite() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a new rank with can_invite false
    state.create_rank(2, false, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB and assigns him the new rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // BOB tries to invite CHARLIE
    start_cheat_caller_address(test_address(), BOB);
    state.invite_member(CHARLIE);
}

#[test]
#[should_panic(expected: "Caller does not have permission to kick")]
fn test_member_without_kick_permission_cannot_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a new rank with can_kick false
    state.create_rank(2, true, false, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB and assigns him the new rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // Owner invites CHARLIE
    state.invite_member(CHARLIE);
    // BOB tries to kick CHARLIE
    start_cheat_caller_address(test_address(), BOB);
    state.kick_member(CHARLIE);
}

#[test]
#[should_panic(expected: "Target member cannot be kicked")]
fn test_cannot_kick_member_with_cannot_be_kicked_rank() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a new rank with can_be_kicked false
    state.create_rank(2, true, true, 2, false);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB and assigns him the new rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // Owner invites CHARLIE
    state.invite_member(CHARLIE);
    // Assign CHARLIE the cannot_be_kicked rank
    let mut charlie_member = state.members.read(CHARLIE);
    charlie_member.rank_id = rank_id;
    state.members.write(CHARLIE, charlie_member);
    // BOB tries to kick CHARLIE
    start_cheat_caller_address(test_address(), BOB);
    state.kick_member(CHARLIE);
}

#[test]
#[should_panic(expected: "Caller is not a guild member")]
fn test_non_member_cannot_invite_or_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // ALICE is not a member
    start_cheat_caller_address(test_address(), ALICE);
    state.invite_member(BOB);
    // Should panic before this, but also test kick
    state.kick_member(BOB);
}

#[test]
#[should_panic(expected: "Target member cannot be kicked")]
fn test_owner_cannot_kick_self() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    start_cheat_caller_address(test_address(), OWNER);

    state.initializer(guild_name, rank_name);

    state.kick_member(OWNER);
}

#[test]
#[should_panic(expected: "Member already exists in the guild")]
fn test_member_cannot_invite_self() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a new rank with can_invite true
    state.create_rank(2, true, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB and assigns him the new rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // BOB tries to invite himself
    start_cheat_caller_address(test_address(), BOB);
    state.invite_member(BOB);
}

#[test]
#[should_panic(expected: "Target member cannot be kicked")]
fn test_member_cannot_kick_self() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates a new rank with can_kick true but can_be_kicked false
    state.create_rank(2, true, true, 2, false);
    let rank_id = state.rank_count.read() - 1_u8;
    // Owner invites BOB and assigns him the new rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // BOB tries to kick himself
    start_cheat_caller_address(test_address(), BOB);
    state.kick_member(BOB);
}


#[test]
#[should_panic(expected: "Caller does not have permission to invite")]
fn test_member_with_invalid_rank_cannot_invite() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner invites BOB and assigns him a non-existent rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = 250_u8; // non-existent rank
    state.members.write(BOB, bob_member);
    // BOB tries to invite CHARLIE
    start_cheat_caller_address(test_address(), BOB);
    state.invite_member(CHARLIE);
}

#[test]
#[should_panic(expected: "Caller does not have permission to kick")]
fn test_member_with_invalid_rank_cannot_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner invites BOB and assigns him a non-existent rank
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = 250_u8; // non-existent rank
    state.members.write(BOB, bob_member);
    // Owner invites CHARLIE
    state.invite_member(CHARLIE);
    // BOB tries to kick CHARLIE
    start_cheat_caller_address(test_address(), BOB);
    state.kick_member(CHARLIE);
}

#[test]
fn test_get_rank_permissions() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Owner creates two more ranks
    state.create_rank(2, true, false, 2, true);
    state.create_rank(3, false, true, 3, false);
    // Call get_rank_permissions
    let ranks = state.get_rank_permissions();

    println!("ranks: {}", ranks.len());
    // There should be 3 ranks
    assert(ranks.len() == 3, 'Should have 3 ranks');
    // Expected ranks
    let expected0 = Rank {
        rank_name: 1, can_invite: true, can_kick: true, promote: 1, can_be_kicked: false,
    };
    let expected1 = Rank {
        rank_name: 2, can_invite: true, can_kick: false, promote: 2, can_be_kicked: true,
    };
    let expected2 = Rank {
        rank_name: 3, can_invite: false, can_kick: true, promote: 3, can_be_kicked: false,
    };
    // Assert all ranks
    assert(*ranks.at(0) == expected0, 'Rank 0 mismatch');
    assert(*ranks.at(1) == expected1, 'Rank 1 mismatch');
    assert(*ranks.at(2) == expected2, 'Rank 2 mismatch');
}

