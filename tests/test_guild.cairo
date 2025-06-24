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

    state.invite_member(ALICE);
}

#[test]
#[should_panic(expected: "Caller is not a guild member")]
fn test_guild_invite_nonowner() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    start_cheat_caller_address(test_address(), BOB);

    state.invite_member(ALICE);
}


#[test]
#[should_panic(expected: "Member already exists in the guild")]
fn test_guild_double_invite() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    state.invite_member(ALICE);

    state.invite_member(ALICE);
}


#[test]
fn test_guild_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    // Create a kickable rank
    state.create_rank(2, true, true, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    // Invite ALICE and assign her the kickable rank
    state.invite_member(ALICE);
    let mut alice_member = state.members.read(ALICE);
    alice_member.rank_id = rank_id;
    state.members.write(ALICE, alice_member);
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
    state.invite_member(BOB);
    let mut bob_member = state.members.read(BOB);
    bob_member.rank_id = rank_id;
    state.members.write(BOB, bob_member);
    // First kick should succeed
    state.kick_member(BOB);
    // Second kick should fail with "Member does not exist in the guild"
    // (the test should expect this panic)
    state.kick_member(BOB);
}

