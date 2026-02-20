use core::num::traits::Zero;
use guilds::interfaces::factory::{IGuildFactoryDispatcher, IGuildFactoryDispatcherTrait};
use guilds::interfaces::guild::{IGuildViewDispatcher, IGuildViewDispatcherTrait};
use guilds::interfaces::token::{IGuildTokenDispatcher, IGuildTokenDispatcherTrait};
use guilds::models::types::GovernorConfig;
use guilds::tests::constants::AsAddressTrait;
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn CREATOR() -> ContractAddress {
    0xCAFE.as_address()
}

fn ALICE() -> ContractAddress {
    0xA11CE.as_address()
}

fn DEPOSIT_TOKEN() -> ContractAddress {
    0xD0.as_address()
}

fn default_governor_config() -> GovernorConfig {
    GovernorConfig {
        voting_delay: 86400,
        voting_period: 259200,
        proposal_threshold: 10000,
        quorum_bps: 1000, // 10%
        timelock_delay: 86400,
    }
}

fn deploy_factory() -> (ContractAddress, IGuildFactoryDispatcher) {
    let guild_class = declare("Guild").unwrap().contract_class();
    let token_class = declare("GuildToken").unwrap().contract_class();
    let governor_class = declare("GuildGovernor").unwrap().contract_class();
    let factory_class = declare("GuildFactory").unwrap().contract_class();

    let mut calldata: Array<felt252> = array![];
    (*guild_class.class_hash).serialize(ref calldata);
    (*token_class.class_hash).serialize(ref calldata);
    (*governor_class.class_hash).serialize(ref calldata);

    let (address, _) = factory_class.deploy(@calldata).unwrap();
    (address, IGuildFactoryDispatcher { contract_address: address })
}

// ========================================================================
// Registry tests (unit-level, no deploy_syscall)
// ========================================================================

#[test]
fn test_factory_deploy() {
    let (_, factory) = deploy_factory();
    assert!(factory.guild_count() == 0);
}

#[test]
fn test_name_not_taken_initially() {
    let (_, factory) = deploy_factory();
    assert!(!factory.is_name_taken('TestGuild'));
}

#[test]
fn test_ticker_not_taken_initially() {
    let (_, factory) = deploy_factory();
    assert!(!factory.is_ticker_taken('TG'));
}

#[test]
fn test_get_all_guilds_empty() {
    let (_, factory) = deploy_factory();
    let guilds = factory.get_all_guilds();
    assert!(guilds.len() == 0);
}

// ========================================================================
// create_guild integration tests
// ========================================================================

#[test]
fn test_create_guild_success() {
    let (factory_addr, factory) = deploy_factory();

    start_cheat_caller_address(factory_addr, CREATOR());

    let (guild_addr, token_addr, governor_addr) = factory
        .create_guild(
            'TestGuild',
            'TG',
            DEPOSIT_TOKEN(),
            0, // deposit_amount (not enforced yet in this implementation)
            1_000_000_000_000_000_000_000_u256, // 1000 tokens
            default_governor_config(),
        );

    stop_cheat_caller_address(factory_addr);

    // --- Verify registry ---
    assert!(factory.guild_count() == 1);
    assert!(factory.is_name_taken('TestGuild'));
    assert!(factory.is_ticker_taken('TG'));

    let entry = factory.get_guild(guild_addr);
    assert!(entry.guild_address == guild_addr);
    assert!(entry.token_address == token_addr);
    assert!(entry.governor_address == governor_addr);
    assert!(entry.name == 'TestGuild');
    assert!(entry.ticker == 'TG');
    assert!(entry.creator == CREATOR());
    assert!(entry.is_active);

    // --- Verify get_all_guilds ---
    let all = factory.get_all_guilds();
    assert!(all.len() == 1);
    assert!(*all.at(0) == guild_addr);

    // --- Verify contracts are wired correctly ---

    // Guild should know its token and governor
    let guild_view = IGuildViewDispatcher { contract_address: guild_addr };
    assert!(guild_view.get_token_address() == token_addr);
    assert!(guild_view.get_governor_address() == governor_addr);
    assert!(guild_view.get_guild_name() == 'TestGuild');
    assert!(guild_view.get_guild_ticker() == 'TG');

    // Creator should be a member with role 0
    let member = guild_view.get_member(CREATOR());
    assert!(member.addr == CREATOR());
    assert!(member.role_id == 0);
    assert!(guild_view.get_member_count() == 1);

    // Token should know its guild and governor
    let token = IGuildTokenDispatcher { contract_address: token_addr };
    assert!(token.get_guild_address() == guild_addr);

    // Creator should have initial supply
    let erc20 = IERC20Dispatcher { contract_address: token_addr };
    assert!(erc20.balance_of(CREATOR()) == 1_000_000_000_000_000_000_000_u256);
}

#[test]
#[should_panic]
fn test_create_guild_duplicate_name() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    factory
        .create_guild(
            'TestGuild', 'TG', DEPOSIT_TOKEN(), 0, 1000, default_governor_config(),
        );

    // Second guild with same name should fail
    factory
        .create_guild(
            'TestGuild', 'TG2', DEPOSIT_TOKEN(), 0, 1000, default_governor_config(),
        );
}

#[test]
#[should_panic]
fn test_create_guild_duplicate_ticker() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    factory
        .create_guild(
            'Guild1', 'TG', DEPOSIT_TOKEN(), 0, 1000, default_governor_config(),
        );

    // Second guild with same ticker should fail
    factory
        .create_guild(
            'Guild2', 'TG', DEPOSIT_TOKEN(), 0, 1000, default_governor_config(),
        );
}

#[test]
#[should_panic]
fn test_create_guild_zero_name() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    factory.create_guild(0, 'TG', DEPOSIT_TOKEN(), 0, 1000, default_governor_config());
}

#[test]
#[should_panic]
fn test_create_guild_zero_ticker() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    factory
        .create_guild('TestGuild', 0, DEPOSIT_TOKEN(), 0, 1000, default_governor_config());
}

#[test]
#[should_panic]
fn test_create_guild_zero_deposit_token() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    let zero: ContractAddress = Zero::zero();
    factory.create_guild('TestGuild', 'TG', zero, 0, 1000, default_governor_config());
}

#[test]
#[should_panic]
fn test_create_guild_zero_supply() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    factory
        .create_guild('TestGuild', 'TG', DEPOSIT_TOKEN(), 0, 0, default_governor_config());
}

#[test]
#[should_panic]
fn test_get_guild_not_found() {
    let (_, factory) = deploy_factory();

    factory.get_guild(0x999.as_address());
}

#[test]
fn test_create_multiple_guilds() {
    let (factory_addr, factory) = deploy_factory();
    start_cheat_caller_address(factory_addr, CREATOR());

    let (guild1, _, _) = factory
        .create_guild(
            'Guild1', 'G1', DEPOSIT_TOKEN(), 0, 1000, default_governor_config(),
        );

    let (guild2, _, _) = factory
        .create_guild(
            'Guild2', 'G2', DEPOSIT_TOKEN(), 0, 2000, default_governor_config(),
        );

    stop_cheat_caller_address(factory_addr);

    assert!(factory.guild_count() == 2);
    assert!(factory.is_name_taken('Guild1'));
    assert!(factory.is_name_taken('Guild2'));
    assert!(!factory.is_name_taken('Guild3'));

    let all = factory.get_all_guilds();
    assert!(all.len() == 2);
    assert!(*all.at(0) == guild1);
    assert!(*all.at(1) == guild2);

    // Both guilds should be independently queryable
    let entry1 = factory.get_guild(guild1);
    assert!(entry1.name == 'Guild1');

    let entry2 = factory.get_guild(guild2);
    assert!(entry2.name == 'Guild2');
}
