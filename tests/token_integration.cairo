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
    let token_name: ByteArray = "TestToken";
    let token_symbol: ByteArray = "TTK";
    let token_supply: u256 = 10000;

    let deployer = test_address();
    start_cheat_caller_address(deployer, deployer);

    let contract = declare("GuildMock").unwrap().contract_class();
    println!("declared contract deploying....");

    let mut calldata = array![];

    guild_name.serialize(ref calldata);
    rank_name.serialize(ref calldata);
    token_name.serialize(ref calldata);
    token_symbol.serialize(ref calldata);
    token_supply.serialize(ref calldata);

    let (contract_address, _) = contract
        .deploy(@calldata)
        .unwrap();
    println!("deployed contract....");

    let dispatcher = IGuildMockDispatcher { contract_address };
}
