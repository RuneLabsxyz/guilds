use core::num::traits::Zero;
use core::serde::Serde;
use openzeppelin_interfaces::governance::extensions::{
    IGovernorSettingsAdminDispatcher, IGovernorSettingsAdminDispatcherTrait,
    IQuorumFractionDispatcher, IQuorumFractionDispatcherTrait,
};
use openzeppelin_interfaces::governor::{IGovernorDispatcher, IGovernorDispatcherTrait, ProposalState};
use openzeppelin_interfaces::votes::{IVotesDispatcher, IVotesDispatcherTrait};
use openzeppelin_utils::bytearray::ByteArrayExtTrait;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address,
};
use starknet::ContractAddress;
use starknet::account::Call;

#[starknet::interface]
pub trait IGuildGovernorView<TState> {
    fn get_guild_address(self: @TState) -> ContractAddress;
}

fn TOKEN_HOLDER() -> ContractAddress {
    starknet::contract_address_const::<0x300>()
}

fn VOTER() -> ContractAddress {
    starknet::contract_address_const::<0x400>()
}

fn GUILD_ADDR() -> ContractAddress {
    starknet::contract_address_const::<0x200>()
}

fn TOKEN_GOVERNOR_ADDR() -> ContractAddress {
    starknet::contract_address_const::<0x100>()
}

fn BASE_TS() -> u64 {
    1_000_000
}

fn VOTING_DELAY() -> u64 {
    10
}

fn VOTING_PERIOD() -> u64 {
    30
}

fn PROPOSAL_THRESHOLD() -> u256 {
    10_000_000_000_000_000_000_u256
}

fn QUORUM_NUMERATOR() -> u256 {
    100_u256
}

fn INITIAL_SUPPLY() -> u256 {
    1_000_000_000_000_000_000_000_u256
}

fn deploy_token() -> ContractAddress {
    let contract = declare("GuildToken").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "GuildToken";
    let symbol: ByteArray = "GT";
    Serde::<ByteArray>::serialize(@name, ref calldata);
    Serde::<ByteArray>::serialize(@symbol, ref calldata);
    Serde::serialize(@INITIAL_SUPPLY(), ref calldata);
    Serde::serialize(@TOKEN_HOLDER(), ref calldata);
    Serde::serialize(@TOKEN_GOVERNOR_ADDR(), ref calldata);
    Serde::serialize(@GUILD_ADDR(), ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn deploy_governor(token_address: ContractAddress) -> ContractAddress {
    let contract = declare("GuildGovernor").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@token_address, ref calldata);
    Serde::serialize(@VOTING_DELAY(), ref calldata);
    Serde::serialize(@VOTING_PERIOD(), ref calldata);
    Serde::serialize(@PROPOSAL_THRESHOLD(), ref calldata);
    Serde::serialize(@QUORUM_NUMERATOR(), ref calldata);
    Serde::serialize(@GUILD_ADDR(), ref calldata);
    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn deploy_system() -> (ContractAddress, ContractAddress) {
    let token_address = deploy_token();
    let governor_address = deploy_governor(token_address);
    (token_address, governor_address)
}

fn set_time(token_address: ContractAddress, governor_address: ContractAddress, timestamp: u64) {
    start_cheat_block_timestamp(token_address, timestamp);
    start_cheat_block_timestamp(governor_address, timestamp);
}

fn delegate_to_self(token_address: ContractAddress, account: ContractAddress, timestamp: u64) {
    let votes = IVotesDispatcher { contract_address: token_address };
    start_cheat_caller_address(token_address, account);
    start_cheat_block_timestamp(token_address, timestamp);
    votes.delegate(account);
}

fn sample_call() -> Call {
    Call { to: GUILD_ADDR(), selector: selector!("some_function"), calldata: array![].span() }
}

fn propose_as_holder(
    token_address: ContractAddress, governor_address: ContractAddress,
) -> (IGovernorDispatcher, felt252) {
    let governor = IGovernorDispatcher { contract_address: governor_address };
    delegate_to_self(token_address, TOKEN_HOLDER(), BASE_TS() + 1);
    set_time(token_address, governor_address, BASE_TS() + 2);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());

    let calls = array![sample_call()];
    let proposal_id = governor.propose(calls.span(), "guild proposal");
    (governor, proposal_id)
}

fn propose_with_calls(
    token_address: ContractAddress,
    governor_address: ContractAddress,
    calls: Span<Call>,
    description: ByteArray,
) -> (IGovernorDispatcher, felt252) {
    let governor = IGovernorDispatcher { contract_address: governor_address };
    delegate_to_self(token_address, TOKEN_HOLDER(), BASE_TS() + 1);
    set_time(token_address, governor_address, BASE_TS() + 2);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());

    let proposal_id = governor.propose(calls, description);
    (governor, proposal_id)
}

#[test]
fn test_governor_deploys_successfully() {
    let (_, governor_address) = deploy_system();
    assert!(governor_address.is_non_zero());
}

#[test]
fn test_voting_delay_configured_correctly() {
    let (_, governor_address) = deploy_system();
    let governor = IGovernorDispatcher { contract_address: governor_address };
    assert!(governor.voting_delay() == VOTING_DELAY());
}

#[test]
fn test_voting_period_configured_correctly() {
    let (_, governor_address) = deploy_system();
    let governor = IGovernorDispatcher { contract_address: governor_address };
    assert!(governor.voting_period() == VOTING_PERIOD());
}

#[test]
fn test_proposal_threshold_configured_correctly() {
    let (_, governor_address) = deploy_system();
    let governor = IGovernorDispatcher { contract_address: governor_address };
    assert!(governor.proposal_threshold() == PROPOSAL_THRESHOLD());
}

#[test]
fn test_guild_address_stored_correctly() {
    let (_, governor_address) = deploy_system();
    let governor = IGuildGovernorViewDispatcher { contract_address: governor_address };
    assert!(governor.get_guild_address() == GUILD_ADDR());
}

#[test]
fn test_quorum_fraction_configured_correctly() {
    let (_, governor_address) = deploy_system();
    let quorum = IQuorumFractionDispatcher { contract_address: governor_address };
    assert!(quorum.current_quorum_numerator() == QUORUM_NUMERATOR());
}

#[test]
fn test_token_holder_with_enough_tokens_can_propose() {
    let (token_address, governor_address) = deploy_system();
    let (_, proposal_id) = propose_as_holder(token_address, governor_address);
    assert!(proposal_id != 0);
}

#[test]
#[should_panic]
fn test_token_holder_without_enough_tokens_cannot_propose() {
    let (token_address, governor_address) = deploy_system();
    let governor = IGovernorDispatcher { contract_address: governor_address };
    delegate_to_self(token_address, VOTER(), BASE_TS() + 1);
    set_time(token_address, governor_address, BASE_TS() + 2);
    start_cheat_caller_address(governor_address, VOTER());
    let calls = array![sample_call()];
    governor.propose(calls.span(), "should fail");
}

#[test]
fn test_proposal_returns_valid_proposal_id() {
    let (token_address, governor_address) = deploy_system();
    let governor = IGovernorDispatcher { contract_address: governor_address };
    delegate_to_self(token_address, TOKEN_HOLDER(), BASE_TS() + 1);
    set_time(token_address, governor_address, BASE_TS() + 2);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());

    let calls = array![sample_call()];
    let proposal_id = governor.propose(calls.span(), "id check");
    let description: ByteArray = "id check";
    let expected_id = governor.hash_proposal(array![sample_call()].span(), description.hash());
    assert!(proposal_id == expected_id);
}

#[test]
fn test_delegated_token_holder_can_vote() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + 3);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    let vote_weight = governor.cast_vote(proposal_id, 1);
    assert!(vote_weight == INITIAL_SUPPLY());
}

#[test]
fn test_vote_with_for_support_counted() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + 3);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    governor.cast_vote(proposal_id, 1);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + VOTING_PERIOD() + 5);
    assert!(governor.state(proposal_id) == ProposalState::Succeeded);
}

#[test]
#[should_panic]
fn test_cannot_vote_twice_on_same_proposal() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + 3);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    governor.cast_vote(proposal_id, 1);
    governor.cast_vote(proposal_id, 1);
}

#[test]
#[should_panic]
fn test_cannot_vote_before_voting_starts() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + 3);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    governor.cast_vote(proposal_id, 1);
}

#[test]
#[should_panic]
fn test_cannot_vote_after_voting_ends() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + VOTING_PERIOD() + 5);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    governor.cast_vote(proposal_id, 1);
}

#[test]
fn test_proposal_starts_as_pending() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);
    assert!(governor.state(proposal_id) == ProposalState::Pending);
}

#[test]
fn test_proposal_becomes_active_after_voting_delay() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);
    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + 3);
    assert!(governor.state(proposal_id) == ProposalState::Active);
}

#[test]
fn test_proposal_becomes_defeated_if_quorum_not_met() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + VOTING_PERIOD() + 5);
    assert!(governor.state(proposal_id) == ProposalState::Defeated);
}

#[test]
fn test_proposal_becomes_succeeded_if_quorum_met_and_for_greater_than_against() {
    let (token_address, governor_address) = deploy_system();
    let (governor, proposal_id) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + 3);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    governor.cast_vote(proposal_id, 1);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + VOTING_PERIOD() + 5);
    assert!(governor.state(proposal_id) == ProposalState::Succeeded);
}

#[test]
fn test_succeeded_proposal_can_be_executed() {
    let (token_address, governor_address) = deploy_system();
    let description: ByteArray = "token ping";
    let (governor, proposal_id) = propose_with_calls(
        token_address,
        governor_address,
        array![
            Call { to: token_address, selector: selector!("ping"), calldata: array![].span() }
        ]
            .span(),
        description.clone(),
    );

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + 3);
    start_cheat_caller_address(governor_address, TOKEN_HOLDER());
    governor.cast_vote(proposal_id, 1);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + VOTING_PERIOD() + 5);
    let calls =
        array![Call { to: token_address, selector: selector!("ping"), calldata: array![].span() }];
    governor.execute(calls.span(), description.hash());

    assert!(governor.state(proposal_id) == ProposalState::Executed);
}

#[test]
#[should_panic]
fn test_defeated_proposal_cannot_be_executed() {
    let (token_address, governor_address) = deploy_system();
    let (governor, _) = propose_as_holder(token_address, governor_address);

    set_time(token_address, governor_address, BASE_TS() + VOTING_DELAY() + VOTING_PERIOD() + 5);
    let calls = array![sample_call()];
    let description: ByteArray = "guild proposal";
    governor.execute(calls.span(), description.hash());
}

#[test]
fn test_governance_can_update_voting_delay() {
    let (_, governor_address) = deploy_system();
    let governor = IGovernorDispatcher { contract_address: governor_address };
    let governor_admin = IGovernorSettingsAdminDispatcher { contract_address: governor_address };
    start_cheat_caller_address(governor_address, governor_address);
    governor_admin.set_voting_delay(42);
    assert!(governor.voting_delay() == 42);
}
