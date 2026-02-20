use core::serde::Serde;
use guilds::interfaces::token::{IGuildTokenDispatcher, IGuildTokenDispatcherTrait};
use openzeppelin_interfaces::erc20::{
    IERC20Dispatcher, IERC20DispatcherTrait, IERC20MetadataDispatcher,
    IERC20MetadataDispatcherTrait,
};
use openzeppelin_interfaces::votes::{IVotesDispatcher, IVotesDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, test_address,
};
use starknet::ContractAddress;

fn HOLDER() -> ContractAddress {
    starknet::contract_address_const::<0x111>()
}

fn GOVERNOR() -> ContractAddress {
    starknet::contract_address_const::<0x222>()
}

fn GUILD() -> ContractAddress {
    starknet::contract_address_const::<0x333>()
}

fn ALICE() -> ContractAddress {
    starknet::contract_address_const::<0x444>()
}

fn BOB() -> ContractAddress {
    starknet::contract_address_const::<0x555>()
}

fn CHARLIE() -> ContractAddress {
    starknet::contract_address_const::<0x666>()
}

fn BASE_TS() -> u64 {
    1_000_000
}

fn THRESHOLD() -> u64 {
    7_776_000
}

fn INITIAL_SUPPLY() -> u256 {
    1_000_000_000_000_000_000_000_u256
}

fn ONE_TOKEN() -> u256 {
    1_000_000_000_000_000_000_u256
}

fn TWO_TOKENS() -> u256 {
    2_000_000_000_000_000_000_u256
}

fn HUNDRED_TOKENS() -> u256 {
    100_000_000_000_000_000_000_u256
}

fn deploy_guild_token() -> (
    ContractAddress,
    IGuildTokenDispatcher,
    IERC20Dispatcher,
    IERC20MetadataDispatcher,
    IVotesDispatcher,
) {
    start_cheat_block_timestamp(test_address(), BASE_TS());

    let contract = declare("GuildToken").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "GuildToken";
    let symbol: ByteArray = "GT";
    Serde::<ByteArray>::serialize(@name, ref calldata);
    Serde::<ByteArray>::serialize(@symbol, ref calldata);
    Serde::serialize(@INITIAL_SUPPLY(), ref calldata);
    Serde::serialize(@HOLDER(), ref calldata);
    Serde::serialize(@GOVERNOR(), ref calldata);
    Serde::serialize(@GUILD(), ref calldata);
    Serde::serialize(@THRESHOLD(), ref calldata);

    let (address, _) = contract.deploy(@calldata).unwrap();
    let guild_token = IGuildTokenDispatcher { contract_address: address };
    let erc20 = IERC20Dispatcher { contract_address: address };
    let metadata = IERC20MetadataDispatcher { contract_address: address };
    let votes = IVotesDispatcher { contract_address: address };

    start_cheat_caller_address(address, HOLDER());
    start_cheat_block_timestamp(address, BASE_TS());
    guild_token.ping();

    (address, guild_token, erc20, metadata, votes)
}

#[test]
fn test_initial_supply_minted_to_holder() {
    let (_, _, erc20, _, _) = deploy_guild_token();
    assert!(erc20.balance_of(HOLDER()) == INITIAL_SUPPLY());
}

#[test]
fn test_name_and_symbol_are_correct() {
    let (_, _, _, metadata, _) = deploy_guild_token();
    assert!(metadata.name() == "GuildToken");
    assert!(metadata.symbol() == "GT");
}

#[test]
fn test_decimals_is_18() {
    let (_, _, _, metadata, _) = deploy_guild_token();
    assert!(metadata.decimals() == 18);
}

#[test]
fn test_transfer_works() {
    let (address, _, erc20, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, HOLDER());
    assert!(erc20.transfer(ALICE(), ONE_TOKEN()));
    assert!(erc20.balance_of(ALICE()) == ONE_TOKEN());
}

#[test]
fn test_transfer_updates_activity_for_both_parties() {
    let (address, guild_token, erc20, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, HOLDER());
    start_cheat_block_timestamp(address, BASE_TS() + 11);
    erc20.transfer(ALICE(), ONE_TOKEN());
    assert!(guild_token.get_last_activity(HOLDER()) == BASE_TS() + 11);
    assert!(guild_token.get_last_activity(ALICE()) == BASE_TS() + 11);
}

#[test]
fn test_initial_holder_has_activity_timestamp_set() {
    let (_, guild_token, _, _, _) = deploy_guild_token();
    assert!(guild_token.get_last_activity(HOLDER()) == BASE_TS());
}

#[test]
fn test_ping_updates_callers_activity() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + 77);
    guild_token.ping();
    assert!(guild_token.get_last_activity(ALICE()) == BASE_TS() + 77);
}

#[test]
fn test_get_last_activity_returns_correct_value() {
    let (_, guild_token, _, _, _) = deploy_guild_token();
    assert!(guild_token.get_last_activity(HOLDER()) == BASE_TS());
}

#[test]
fn test_transfer_updates_sender_activity() {
    let (address, guild_token, erc20, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, HOLDER());
    start_cheat_block_timestamp(address, BASE_TS() + 100);
    erc20.transfer(ALICE(), ONE_TOKEN());
    assert!(guild_token.get_last_activity(HOLDER()) == BASE_TS() + 100);
}

#[test]
fn test_transfer_updates_recipient_activity() {
    let (address, guild_token, erc20, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, HOLDER());
    start_cheat_block_timestamp(address, BASE_TS() + 101);
    erc20.transfer(ALICE(), ONE_TOKEN());
    assert!(guild_token.get_last_activity(ALICE()) == BASE_TS() + 101);
}

#[test]
fn test_flag_inactive_succeeds_after_threshold() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());
    assert!(guild_token.is_flagged_inactive(HOLDER()));
}

#[test]
#[should_panic]
fn test_flag_inactive_fails_if_still_active() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD());
    guild_token.flag_inactive(HOLDER());
}

#[test]
#[should_panic]
fn test_flag_inactive_fails_if_no_activity_record() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, BOB());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(ALICE());
}

#[test]
#[should_panic]
fn test_flag_inactive_fails_if_already_flagged() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());
    guild_token.flag_inactive(HOLDER());
}

#[test]
fn test_clear_inactivity_flag_by_flagged_account() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());

    start_cheat_caller_address(address, HOLDER());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 2);
    guild_token.clear_inactivity_flag();

    assert!(!guild_token.is_flagged_inactive(HOLDER()));
    assert!(guild_token.get_last_activity(HOLDER()) == BASE_TS() + THRESHOLD() + 2);
}

#[test]
#[should_panic]
fn test_clear_inactivity_flag_fails_if_not_flagged() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    guild_token.clear_inactivity_flag();
}

#[test]
fn test_is_flagged_inactive_returns_correct_value() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    assert!(!guild_token.is_flagged_inactive(HOLDER()));
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());
    assert!(guild_token.is_flagged_inactive(HOLDER()));
}

#[test]
fn test_active_supply_excludes_inactive_balances() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());
    assert!(guild_token.active_supply() == 0);
}

#[test]
fn test_governor_can_mint() {
    let (address, _, erc20, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, GOVERNOR());
    let before = erc20.balance_of(ALICE());
    let token = ONE_TOKEN();
    let guild_token = IGuildTokenDispatcher { contract_address: address };
    guild_token.mint(ALICE(), token);
    assert!(erc20.balance_of(ALICE()) == before + token);
}

#[test]
#[should_panic]
fn test_non_governor_cannot_mint() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    guild_token.mint(ALICE(), ONE_TOKEN());
}

#[test]
fn test_governor_can_burn() {
    let (address, _, erc20, _, _) = deploy_guild_token();
    let guild_token = IGuildTokenDispatcher { contract_address: address };
    start_cheat_caller_address(address, GOVERNOR());
    guild_token.burn(HOLDER(), ONE_TOKEN());
    assert!(erc20.balance_of(HOLDER()) == INITIAL_SUPPLY() - ONE_TOKEN());
}

#[test]
#[should_panic]
fn test_non_governor_cannot_burn() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    guild_token.burn(HOLDER(), ONE_TOKEN());
}

#[test]
fn test_burn_of_flagged_account_reduces_inactive_balance() {
    let (address, guild_token, _, _, _) = deploy_guild_token();

    start_cheat_caller_address(address, GOVERNOR());
    guild_token.mint(ALICE(), HUNDRED_TOKENS());

    start_cheat_caller_address(address, BOB());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());

    start_cheat_caller_address(address, GOVERNOR());
    guild_token.burn(HOLDER(), HUNDRED_TOKENS());

    assert!(guild_token.active_supply() == HUNDRED_TOKENS());
}

#[test]
fn test_mint_updates_recipient_activity() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, GOVERNOR());
    start_cheat_block_timestamp(address, BASE_TS() + 500);
    guild_token.mint(ALICE(), TWO_TOKENS());
    assert!(guild_token.get_last_activity(ALICE()) == BASE_TS() + 500);
}

#[test]
fn test_delegation_works() {
    let (address, _, _, _, votes) = deploy_guild_token();
    start_cheat_caller_address(address, HOLDER());
    votes.delegate(HOLDER());
    assert!(votes.get_votes(HOLDER()) == INITIAL_SUPPLY());
}

#[test]
fn test_get_votes_is_zero_before_delegation() {
    let (_, _, _, _, votes) = deploy_guild_token();
    assert!(votes.get_votes(HOLDER()) == 0);
}

#[test]
fn test_get_votes_equals_balance_after_self_delegation() {
    let (address, _, erc20, _, votes) = deploy_guild_token();
    start_cheat_caller_address(address, HOLDER());
    votes.delegate(HOLDER());
    assert!(votes.get_votes(HOLDER()) == erc20.balance_of(HOLDER()));
}

#[test]
fn test_transfer_updates_voting_power() {
    let (address, _, erc20, _, votes) = deploy_guild_token();

    start_cheat_caller_address(address, HOLDER());
    votes.delegate(HOLDER());

    start_cheat_caller_address(address, ALICE());
    votes.delegate(ALICE());

    start_cheat_caller_address(address, HOLDER());
    erc20.transfer(ALICE(), HUNDRED_TOKENS());

    assert!(votes.get_votes(HOLDER()) == INITIAL_SUPPLY() - HUNDRED_TOKENS());
    assert!(votes.get_votes(ALICE()) == HUNDRED_TOKENS());
}

#[test]
fn test_get_guild_address_returns_correct_value() {
    let (_, guild_token, _, _, _) = deploy_guild_token();
    assert!(guild_token.get_guild_address() == GUILD());
}

#[test]
fn test_active_supply_without_inactive_equals_total_supply() {
    let (_, guild_token, erc20, _, _) = deploy_guild_token();
    assert!(guild_token.active_supply() == erc20.total_supply());
}

#[test]
fn test_multiple_accounts_flagged_and_cleared_correctly() {
    let (address, guild_token, erc20, _, _) = deploy_guild_token();

    start_cheat_caller_address(address, HOLDER());
    erc20.transfer(ALICE(), HUNDRED_TOKENS());
    erc20.transfer(BOB(), ONE_TOKEN());

    start_cheat_caller_address(address, CHARLIE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(ALICE());
    guild_token.flag_inactive(BOB());

    let supply_after_flag = guild_token.active_supply();
    assert!(supply_after_flag == INITIAL_SUPPLY() - HUNDRED_TOKENS() - ONE_TOKEN());

    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 2);
    guild_token.clear_inactivity_flag();

    assert!(guild_token.is_flagged_inactive(ALICE()) == false);
    assert!(guild_token.is_flagged_inactive(BOB()));
    assert!(guild_token.active_supply() == INITIAL_SUPPLY() - ONE_TOKEN());
}

#[test]
fn test_transfer_from_flagged_account_increases_active_supply() {
    let (address, guild_token, erc20, _, _) = deploy_guild_token();

    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());
    assert!(guild_token.active_supply() == 0);

    start_cheat_caller_address(address, HOLDER());
    erc20.transfer(ALICE(), HUNDRED_TOKENS());

    assert!(guild_token.active_supply() == HUNDRED_TOKENS());
}

#[test]
fn test_transfer_to_flagged_account_decreases_active_supply() {
    let (address, guild_token, erc20, _, _) = deploy_guild_token();

    start_cheat_caller_address(address, HOLDER());
    erc20.transfer(ALICE(), HUNDRED_TOKENS());

    start_cheat_caller_address(address, BOB());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(ALICE());
    assert!(guild_token.active_supply() == INITIAL_SUPPLY() - HUNDRED_TOKENS());

    start_cheat_caller_address(address, HOLDER());
    erc20.transfer(ALICE(), ONE_TOKEN());

    assert!(guild_token.active_supply() == INITIAL_SUPPLY() - HUNDRED_TOKENS() - ONE_TOKEN());
}

#[test]
fn test_get_inactivity_threshold_returns_configured_value() {
    let (_, guild_token, _, _, _) = deploy_guild_token();
    assert!(guild_token.get_inactivity_threshold() == THRESHOLD());
}

#[test]
fn test_get_inactivity_flag_returns_details() {
    let (address, guild_token, _, _, _) = deploy_guild_token();
    start_cheat_caller_address(address, ALICE());
    start_cheat_block_timestamp(address, BASE_TS() + THRESHOLD() + 1);
    guild_token.flag_inactive(HOLDER());

    let flag = guild_token.get_inactivity_flag(HOLDER());
    assert!(flag.flagged_at == BASE_TS() + THRESHOLD() + 1);
    assert!(flag.flagged_by == ALICE());
}
