use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::{GuildMetadataImpl, InternalImpl};
use guilds::guild::interface::IGuild;
use guilds::mocks::guild::GuildMock;
use guilds::tests::constants::{ALICE, BOB, CHARLIE, OWNER};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, test_address,
};
use starknet::ContractAddress;


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
#[should_panic(expected: "Only owner can invite members")]
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

    state.invite_member(ALICE);

    state.kick_member(ALICE);
}
#[test]
#[should_panic(expected: "Member does not exist in the guild")]
fn test_guild_double_kick() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    state.invite_member(ALICE);

    state.kick_member(ALICE);
    state.kick_member(ALICE);
}

