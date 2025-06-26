use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::{GuildMetadataImpl, InternalImpl};
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
fn test_guild_initializer() {
    // Create an in-memory test state for the Guild component
    let mut state = COMPONENT_STATE();

    // Hardcode the guild name
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;

    // Call the initializer
    state.initializer(guild_name, rank_name);

    assert_eq!(state.get_guild_name(), guild_name, "Guild name should match the initialized value");
}

#[test]
fn test_guild_invite() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    state.create_rank(2, true, true, 2, true);
    state.invite_member(ALICE, Option::None);
    start_cheat_caller_address(test_address(), ALICE);
    state.accept_invite();
}

#[test]
#[should_panic(expected: "Caller is not a guild member")]
fn test_guild_invite_nonowner() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    start_cheat_caller_address(test_address(), BOB);

    state.invite_member(ALICE, Option::None);
}


#[test]
#[should_panic(expected: "Member already exists in the guild")]
fn test_guild_double_invite() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    start_cheat_caller_address(test_address(), OWNER);
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, true, 2, true);

    state.invite_member(ALICE, Option::None);
    start_cheat_caller_address(test_address(), ALICE);
    state.accept_invite();

    start_cheat_caller_address(test_address(), OWNER);
    state.invite_member(ALICE, Option::None);
}


#[test]
fn test_guild_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    start_cheat_caller_address(test_address(), OWNER);

    state.initializer(guild_name, rank_name);
    // Create a kickable rank
    state.create_rank(2, true, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Invite ALICE and assign her the kickable rank
    state.invite_member(ALICE, Option::Some(rank_id));
    start_cheat_caller_address(test_address(), ALICE);
    state.accept_invite();
    start_cheat_caller_address(test_address(), OWNER);
    state.kick_member(ALICE);
}

#[test]
#[should_panic(expected: "Target member does not exist in the guild")]
fn test_phantom_guild_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    state.kick_member(ALICE);
}

#[test]
#[should_panic(expected: "Target member does not exist in the guild")]
fn test_guild_double_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Create a kickable rank
    state.create_rank(2, true, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Invite BOB and assign him the kickable rank
    state.invite_member(BOB, Option::Some(rank_id));
    // First kick should succeed
    state.kick_member(BOB);
    // Second kick should fail with "Member does not exist in the guild"
    // (the test should expect this panic)
    state.kick_member(BOB);
}

#[test]
fn test_promote_member_success() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    start_cheat_caller_address(test_address(), OWNER);
    state.initializer(guild_name, rank_name);
    // Create two more ranks
    state.create_rank(2, true, true, 2, true);
    state.create_rank(3, true, true, 3, true);
    // Invite ALICE and assign her the lowest rank
    let lowest_rank = state.rank_count.read() - 1_u8;
    state.invite_member(ALICE, Option::Some(lowest_rank));
    start_cheat_caller_address(test_address(), ALICE);
    state.accept_invite();
    // Promote ALICE to rank 1 (higher than lowest)
    start_cheat_caller_address(test_address(), OWNER);
    state.promote_member(ALICE, 1_u8);
    let member = state.members.read(ALICE);
    assert(member.rank_id == 1_u8, 'Success');
}

#[test]
#[should_panic(expected: "Can only promote to a lower rank")]
fn test_promote_member_to_higher_or_same_rank_should_fail() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    start_cheat_caller_address(test_address(), OWNER);
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, true, 2, true);
    // Invite ALICE and assign her the lowest rank
    let lowest_rank = state.rank_count.read() - 1_u8;
    state.invite_member(ALICE, Option::Some(lowest_rank));
    start_cheat_caller_address(test_address(), ALICE);
    state.accept_invite();
    // ALICE tries to promote herself to the same rank (should fail)
    state.promote_member(ALICE, lowest_rank);
}

#[test]
#[should_panic(expected: "Target member does not exist in the guild")]
fn test_promote_non_member_should_fail() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    start_cheat_caller_address(test_address(), OWNER);
    state.initializer(guild_name, rank_name);
    // Try to promote BOB who is not a member
    state.promote_member(BOB, 1_u8);
}

#[test]
#[should_panic(expected: "Target member does not exist in the guild")]
fn test_non_member_cannot_promote() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, true, 2, true);
    // Invite ALICE and assign her the lowest rank
    let lowest_rank = state.rank_count.read() - 1_u8;
    state.invite_member(ALICE, Option::Some(lowest_rank));
    start_cheat_caller_address(test_address(), ALICE);
    state.accept_invite();
    // BOB (not a member) tries to promote ALICE
    start_cheat_caller_address(test_address(), BOB);
    state.promote_member(ALICE, 1_u8);
}

