use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::{GuildMetadataImpl, InternalImpl};
use guilds::guild::interface::IGuild;
use guilds::mocks::guild::GuildMock;
use snforge_std::{start_cheat_caller_address, test_address};
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

    // Call the initializer
    state.initializer(guild_name);

    assert_eq!(state.get_guild_name(), guild_name, "Guild name should match the initialized value");
}

#[test]
fn test_guild_invite() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    state.initializer(guild_name);

    state.invite_member(123.try_into().unwrap());
}
