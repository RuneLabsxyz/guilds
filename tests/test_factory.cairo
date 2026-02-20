use core::serde::Serde;
use guilds::interfaces::factory::{IGuildFactoryDispatcher, IGuildFactoryDispatcherTrait};
use guilds::interfaces::guild::{IGuildViewDispatcher, IGuildViewDispatcherTrait};
use guilds::interfaces::token::{IGuildTokenDispatcher, IGuildTokenDispatcherTrait};
use guilds::models::types::GovernorConfig;
use guilds::tests::constants::AsAddressTrait;
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
};
use starknet::{ClassHash, ContractAddress};

fn CREATOR() -> ContractAddress {
    0x111.as_address()
}

fn OTHER() -> ContractAddress {
    0x222.as_address()
}

fn MIN_DEPOSIT() -> u256 {
    100_u256
}

fn ONE_THOUSAND() -> u256 {
    1_000_u256
}

fn default_governor_config() -> GovernorConfig {
    GovernorConfig {
        voting_delay: 1,
        voting_period: 60,
        proposal_threshold: 1_u256,
        quorum_bps: 1_000,
        timelock_delay: 0,
    }
}

fn class_hash_of(contract_name: ByteArray) -> ClassHash {
    *declare(contract_name).unwrap().contract_class().class_hash
}

fn deploy_factory(min_deposit: u256) -> (ContractAddress, IGuildFactoryDispatcher) {
    let guild_class_hash = class_hash_of("Guild");
    let token_class_hash = class_hash_of("GuildToken");
    let governor_class_hash = class_hash_of("GuildGovernor");

    let factory_class = declare("GuildFactory").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@guild_class_hash, ref calldata);
    Serde::serialize(@token_class_hash, ref calldata);
    Serde::serialize(@governor_class_hash, ref calldata);
    Serde::serialize(@min_deposit, ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);

    let (address, _) = factory_class.deploy(@calldata).unwrap();
    (address, IGuildFactoryDispatcher { contract_address: address })
}

fn deploy_deposit_token(holder: ContractAddress) -> (ContractAddress, IERC20Dispatcher) {
    let token_class = declare("GuildToken").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "DepositToken";
    let symbol: ByteArray = "DPT";

    Serde::<ByteArray>::serialize(@name, ref calldata);
    Serde::<ByteArray>::serialize(@symbol, ref calldata);
    Serde::serialize(@(1_000_000_u256), ref calldata);
    Serde::serialize(@holder, ref calldata);
    Serde::serialize(@holder, ref calldata);
    Serde::serialize(@holder, ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);

    let (address, _) = token_class.deploy(@calldata).unwrap();
    (address, IERC20Dispatcher { contract_address: address })
}

fn approve_factory(
    token_address: ContractAddress,
    token: IERC20Dispatcher,
    owner: ContractAddress,
    factory: ContractAddress,
    amount: u256,
) {
    start_cheat_caller_address(token_address, owner);
    token.approve(factory, amount);
}

#[test]
fn test_create_guild_registers_entry_and_wires_addresses() {
    let (factory_address, factory) = deploy_factory(MIN_DEPOSIT());
    let (deposit_token_address, deposit_token) = deploy_deposit_token(CREATOR());

    approve_factory(
        deposit_token_address, deposit_token, CREATOR(), factory_address, ONE_THOUSAND(),
    );

    start_cheat_caller_address(factory_address, CREATOR());
    let (guild_address, token_address, governor_address) = factory
        .create_guild(
            'AlphaGuild',
            'ALP',
            deposit_token_address,
            ONE_THOUSAND(),
            10_000_u256,
            default_governor_config(),
        );

    let entry = factory.get_guild(guild_address);
    assert!(entry.guild_address == guild_address);
    assert!(entry.token_address == token_address);
    assert!(entry.governor_address == governor_address);
    assert!(entry.creator == CREATOR());
    assert!(entry.name == 'AlphaGuild');
    assert!(entry.ticker == 'ALP');
    assert!(entry.is_active);
    assert!(factory.guild_count() == 1);
    assert!(factory.is_name_taken('AlphaGuild'));
    assert!(factory.is_ticker_taken('ALP'));

    let guild_view = IGuildViewDispatcher { contract_address: guild_address };
    let guild_token = IGuildTokenDispatcher { contract_address: token_address };

    assert!(guild_view.get_governor_address() == governor_address);
    assert!(guild_view.get_token_address() == token_address);
    assert!(guild_token.get_guild_address() == guild_address);

    assert!(deposit_token.balance_of(guild_address) == ONE_THOUSAND());
    assert!(IERC20Dispatcher { contract_address: token_address }.balance_of(CREATOR()) == 10_000_u256);
}

#[test]
#[should_panic]
fn test_create_guild_fails_when_name_taken() {
    let (factory_address, factory) = deploy_factory(MIN_DEPOSIT());
    let (deposit_token_address, deposit_token) = deploy_deposit_token(CREATOR());

    approve_factory(
        deposit_token_address, deposit_token, CREATOR(), factory_address, ONE_THOUSAND(),
    );

    start_cheat_caller_address(factory_address, CREATOR());
    let _ = factory
        .create_guild(
            'AlphaGuild',
            'ALP',
            deposit_token_address,
            ONE_THOUSAND(),
            10_000_u256,
            default_governor_config(),
        );

    start_cheat_caller_address(factory_address, OTHER());
    let _ = factory
        .create_guild(
            'AlphaGuild',
            'BTA',
            deposit_token_address,
            ONE_THOUSAND(),
            10_000_u256,
            default_governor_config(),
        );
}

#[test]
#[should_panic]
fn test_create_guild_fails_when_ticker_taken() {
    let (factory_address, factory) = deploy_factory(MIN_DEPOSIT());
    let (deposit_token_address, deposit_token) = deploy_deposit_token(CREATOR());

    approve_factory(
        deposit_token_address, deposit_token, CREATOR(), factory_address, ONE_THOUSAND(),
    );

    start_cheat_caller_address(factory_address, CREATOR());
    let _ = factory
        .create_guild(
            'AlphaGuild',
            'ALP',
            deposit_token_address,
            ONE_THOUSAND(),
            10_000_u256,
            default_governor_config(),
        );

    start_cheat_caller_address(factory_address, OTHER());
    let _ = factory
        .create_guild(
            'BetaGuild',
            'ALP',
            deposit_token_address,
            ONE_THOUSAND(),
            10_000_u256,
            default_governor_config(),
        );
}

#[test]
#[should_panic]
fn test_create_guild_fails_when_deposit_below_minimum() {
    let (factory_address, factory) = deploy_factory(2_000_u256);
    let (deposit_token_address, deposit_token) = deploy_deposit_token(CREATOR());

    approve_factory(
        deposit_token_address, deposit_token, CREATOR(), factory_address, ONE_THOUSAND(),
    );

    start_cheat_caller_address(factory_address, CREATOR());
    let _ = factory
        .create_guild(
            'SmallGuild',
            'SML',
            deposit_token_address,
            ONE_THOUSAND(),
            10_000_u256,
            default_governor_config(),
        );
}
