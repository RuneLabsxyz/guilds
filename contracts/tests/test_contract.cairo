use guilds::guild::manage::GuildManagement::{
    IGuildManagementDispatcher, IGuildManagementDispatcherTrait,
};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};

#[test]
fn deploy_and_create_guild() {
    // Declare the contract by its module name
    let contract = declare("GuildManagement").unwrap().contract_class();

    // Deploy the contract (no constructor arguments in this contract)
    let (contract_address, _) = contract.deploy(@array![]).unwrap();

    // Create a dispatcher to interact with the deployed contract
    let dispatcher = IGuildManagementDispatcher { contract_address };

    // Call the create_guild function
    let guild_id = dispatcher.create_guild();

    // Check the returned guild_id is 0 (since it starts at 0)
    assert(guild_id == 0, 'First guild_id should be 0');
    // You can add more calls and assertions here to continue testing.
}

#[test]
fn invite_user_to_guild() {
    // Declare the contract by its module name
    let contract = declare("GuildManagement").unwrap().contract_class();

    // Deploy the contract (no constructor arguments in this contract)
    let (contract_address, _) = contract.deploy(@array![]).unwrap();

    // Create a dispatcher to interact with the deployed contract
    let dispatcher = IGuildManagementDispatcher { contract_address };

    // Create a guild first
    let guild_id = dispatcher.create_guild();

    // Invite a user to the guild
    dispatcher.invite_to_guild(guild_id, 123.try_into().unwrap());

    // swap
    start_cheat_caller_address(contract_address, 123.try_into().unwrap());

    dispatcher.accept_invite(guild_id);
}
