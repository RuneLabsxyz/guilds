use core::num::traits::Zero;
use core::serde::Serde;
use guilds::interfaces::factory::{IGuildFactoryDispatcher, IGuildFactoryDispatcherTrait};
use guilds::models::constants::ActionType;
use guilds::models::types::{GovernorConfig, Role};
use guilds::tests::constants::AsAddressTrait;
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use starknet::{ClassHash, ContractAddress, SyscallResultTrait, syscalls};

fn DEPLOYER() -> ContractAddress {
    0x100.as_address()
}

fn TOKEN() -> ContractAddress {
    0x200.as_address()
}

fn governor_config() -> GovernorConfig {
    GovernorConfig {
        voting_delay: 10,
        voting_period: 30,
        proposal_threshold: 1_000_u256,
        quorum_bps: 1_000,
        timelock_delay: 0,
    }
}

fn founder_role() -> Role {
    Role {
        name: 'founder',
        can_invite: true,
        can_kick: true,
        can_promote_depth: 255,
        can_be_kicked: false,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        payout_weight: 500,
    }
}

fn deployed_class_hash(address: ContractAddress) -> ClassHash {
    syscalls::get_class_hash_at_syscall(address).unwrap_syscall()
}

fn deploy_guild_for_hash() -> ContractAddress {
    let contract = declare("Guild").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@'TmpGuild', ref calldata);
    Serde::serialize(@'TMP', ref calldata);
    Serde::serialize(@TOKEN(), ref calldata);
    Serde::serialize(@DEPLOYER(), ref calldata);
    Serde::serialize(@DEPLOYER(), ref calldata);
    Serde::serialize(@founder_role(), ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn deploy_token_for_hash() -> ContractAddress {
    let contract = declare("GuildToken").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "GuildToken";
    let symbol: ByteArray = "GT";
    Serde::<ByteArray>::serialize(@name, ref calldata);
    Serde::<ByteArray>::serialize(@symbol, ref calldata);
    Serde::serialize(@1_000_000_u256, ref calldata);
    Serde::serialize(@DEPLOYER(), ref calldata);
    Serde::serialize(@DEPLOYER(), ref calldata);
    Serde::serialize(@DEPLOYER(), ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn deploy_governor_for_hash(token_address: ContractAddress) -> ContractAddress {
    let contract = declare("GuildGovernor").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@token_address, ref calldata);
    Serde::serialize(@10_u64, ref calldata);
    Serde::serialize(@30_u64, ref calldata);
    Serde::serialize(@1_000_u256, ref calldata);
    Serde::serialize(@1_000_u256, ref calldata);
    Serde::serialize(@DEPLOYER(), ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn deploy_factory() -> (ContractAddress, IGuildFactoryDispatcher) {
    let guild_hash_source = deploy_guild_for_hash();
    let token_hash_source = deploy_token_for_hash();
    let governor_hash_source = deploy_governor_for_hash(token_hash_source);

    let guild_class_hash = deployed_class_hash(guild_hash_source);
    let token_class_hash = deployed_class_hash(token_hash_source);
    let governor_class_hash = deployed_class_hash(governor_hash_source);

    let factory_decl = declare("GuildFactory").unwrap().contract_class();

    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@guild_class_hash, ref calldata);
    Serde::serialize(@token_class_hash, ref calldata);
    Serde::serialize(@governor_class_hash, ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);

    let (address, _) = factory_decl.deploy(@calldata).unwrap();
    (address, IGuildFactoryDispatcher { contract_address: address })
}

#[test]
fn test_create_guild_registers_entry_and_indexes() {
    let (factory_address, factory) = deploy_factory();
    start_cheat_caller_address(factory_address, DEPLOYER());

    let (guild_address, token_address, governor_address) = factory
        .create_guild('GuildOne', 'G1', TOKEN(), 10_u256, 1_000_000_u256, governor_config());

    assert!(guild_address != Zero::zero());
    assert!(token_address != Zero::zero());
    assert!(governor_address != Zero::zero());

    let entry = factory.get_guild(guild_address);
    assert!(entry.guild_address == guild_address);
    assert!(entry.token_address == token_address);
    assert!(entry.governor_address == governor_address);
    assert!(entry.name == 'GuildOne');
    assert!(entry.ticker == 'G1');
    assert!(entry.creator == DEPLOYER());
    assert!(entry.is_active);

    assert!(factory.is_name_taken('GuildOne'));
    assert!(factory.is_ticker_taken('G1'));
    assert!(factory.guild_count() == 1);

    let all = factory.get_all_guilds();
    assert!(all.len() == 1);
    assert!(*all.at(0) == guild_address);
}

#[test]
#[should_panic]
fn test_create_guild_rejects_duplicate_name() {
    let (factory_address, factory) = deploy_factory();
    start_cheat_caller_address(factory_address, DEPLOYER());

    let _ = factory
        .create_guild('GuildOne', 'G1', TOKEN(), 10_u256, 1_000_000_u256, governor_config());

    let _ = factory
        .create_guild('GuildOne', 'G2', TOKEN(), 10_u256, 1_000_000_u256, governor_config());
}

#[test]
#[should_panic]
fn test_create_guild_rejects_duplicate_ticker() {
    let (factory_address, factory) = deploy_factory();
    start_cheat_caller_address(factory_address, DEPLOYER());

    let _ = factory
        .create_guild('GuildOne', 'G1', TOKEN(), 10_u256, 1_000_000_u256, governor_config());

    let _ = factory
        .create_guild('GuildTwo', 'G1', TOKEN(), 10_u256, 1_000_000_u256, governor_config());
}
