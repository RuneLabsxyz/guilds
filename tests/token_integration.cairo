use core::array::ArrayTrait;
use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::{GuildMetadataImpl, InternalImpl, Rank};
use guilds::guild::interface::IGuild;
use guilds::mocks::guild::{GuildMock, IGuildMockDispatcher};
use guilds::tests::constants::{ALICE, BOB, CHARLIE, OWNER, TOKEN_ADDRESS};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, test_address,
};
use starknet::ContractAddress;
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};

type ComponentState = GuildComponent::ComponentState<GuildMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    GuildComponent::component_state_for_testing()
}

#[test]
fn test_guild_token_address_matches_erc20() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    // Simulate a deployed ERC20 token address (in real deployment, this would be the actual
    // contract address)

    // Initialize the guild with the token address
    state.initializer(guild_name, rank_name, Option::Some(TOKEN_ADDRESS));

    // Assert that the guild's token address matches the one provided
    assert(state.token_address.read() == TOKEN_ADDRESS, 'Guild matches ERC20 tokens');
}

#[test]
fn test_guildmock_constructor_token_address() {
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    let token_name: felt252 = 0x54657374546f6b656e; // "TestToken" as hex
    let token_symbol: felt252 = 0x54544b; // "TTK" as hex
    let token_supply: felt252 = 10000;

    let deployer = test_address();
    start_cheat_caller_address(deployer, deployer);

    let contract = declare("GuildMock").unwrap().contract_class();
    let (contract_address, _) = contract
        .deploy(@array![guild_name, rank_name, token_name, token_symbol, token_supply])
        .unwrap();

    let dispatcher = IGuildMockDispatcher { contract_address };
}
