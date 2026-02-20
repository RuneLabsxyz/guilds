use core::ops::{Deref, DerefMut};
use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::InternalImpl;
use guilds::mocks::guild::GuildMock;
use guilds::models::constants::ActionType;
use guilds::models::types::{Member, Role};
use snforge_std::{start_cheat_block_timestamp, start_cheat_caller_address, test_address};
use starknet::ContractAddress;
use starknet::storage::{
    StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess, StorageTrait, StorageTraitMut,
};

// ========================================================================
// Helpers
// ========================================================================

fn FOUNDER() -> ContractAddress {
    starknet::contract_address_const::<0x100>()
}

fn GOVERNOR() -> ContractAddress {
    starknet::contract_address_const::<0x200>()
}

fn TOKEN() -> ContractAddress {
    starknet::contract_address_const::<0x300>()
}

fn ALICE() -> ContractAddress {
    starknet::contract_address_const::<0x400>()
}

fn BOB() -> ContractAddress {
    starknet::contract_address_const::<0x500>()
}

fn OUTSIDER() -> ContractAddress {
    starknet::contract_address_const::<0x600>()
}

type TestState = GuildMock::ContractState;

fn COMPONENT_STATE() -> TestState {
    GuildMock::contract_state_for_testing()
}

fn guild_storage(state: @TestState) -> GuildComponent::StorageStorageBase {
    state.guild.deref().storage()
}

fn guild_storage_mut(ref state: TestState) -> GuildComponent::StorageStorageBaseMut {
    state.guild.deref_mut().storage_mut()
}

fn default_founder_role() -> Role {
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

fn scorer_role() -> Role {
    Role {
        name: 'scorer',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::SCORE,
        spending_limit: 0,
        payout_weight: 100,
    }
}

fn no_score_role() -> Role {
    Role {
        name: 'member',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::TRANSFER,
        spending_limit: 100,
        payout_weight: 100,
    }
}

fn setup_guild() -> TestState {
    let mut state = COMPONENT_STATE();
    start_cheat_caller_address(test_address(), FOUNDER());
    state
        .guild
        .initializer('TestGuild', 'TG', TOKEN(), GOVERNOR(), FOUNDER(), default_founder_role());
    state
}

fn add_member(ref state: TestState, addr: ContractAddress, role_id: u8) {
    let mut storage = guild_storage_mut(ref state);
    let member = Member { addr, role_id, joined_at: 0 };
    storage.members.write(addr, member);
    storage.member_count.write(storage.member_count.read() + 1);
    let role = storage.roles.read(role_id);
    let weight: u32 = role.payout_weight.into();
    storage.total_payout_weight.write(storage.total_payout_weight.read() + weight);
    storage.role_member_count.write(role_id, storage.role_member_count.read(role_id) + 1);
}

// ========================================================================
// create_season tests
// ========================================================================

#[test]
fn test_create_season_by_governor() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let season_id = state.guild.create_season('Season1', 100, 200);

    assert!(season_id == 0);
    let season = guild_storage(@state).seasons.read(0);
    assert!(season.name == 'Season1');
    assert!(season.starts_at == 100);
    assert!(season.ends_at == 200);
    assert!(!season.finalized);
    assert!(guild_storage(@state).season_count.read() == 1);
}

#[test]
fn test_create_season_open_ended() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let season_id = state.guild.create_season('OpenSeason', 50, 0);

    assert!(season_id == 0);
    let season = guild_storage(@state).seasons.read(0);
    assert!(season.ends_at == 0);
}

#[test]
fn test_create_multiple_seasons() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    let s0 = state.guild.create_season('S1', 100, 200);
    let s1 = state.guild.create_season('S2', 300, 400);

    assert!(s0 == 0);
    assert!(s1 == 1);
    assert!(guild_storage(@state).season_count.read() == 2);
    assert!(guild_storage(@state).seasons.read(0).name == 'S1');
    assert!(guild_storage(@state).seasons.read(1).name == 'S2');
}

#[test]
#[should_panic]
fn test_create_season_non_governor_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.create_season('Season1', 100, 200);
}

#[test]
#[should_panic]
fn test_create_season_zero_name_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season(0, 100, 200);
}

#[test]
#[should_panic]
fn test_create_season_ends_before_starts_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Bad', 200, 100);
}

#[test]
#[should_panic]
fn test_create_season_dissolved_guild_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.dissolve();
    state.guild.create_season('Season1', 100, 200);
}

// ========================================================================
// finalize_season tests
// ========================================================================

#[test]
fn test_finalize_season_by_governor() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());

    state.guild.create_season('Season1', 100, 200);
    state.guild.finalize_season(0);

    let season = guild_storage(@state).seasons.read(0);
    assert!(season.finalized);
}

#[test]
#[should_panic]
fn test_finalize_season_non_governor_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 100, 200);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_season(0);
}

#[test]
#[should_panic]
fn test_finalize_nonexistent_season_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.finalize_season(0);
}

#[test]
#[should_panic]
fn test_finalize_already_finalized_season_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 100, 200);
    state.guild.finalize_season(0);
    state.guild.finalize_season(0);
}

#[test]
#[should_panic]
fn test_finalize_season_dissolved_guild_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 100, 200);
    state.guild.dissolve();
    state.guild.finalize_season(0);
}

// ========================================================================
// record_score tests
// ========================================================================

#[test]
fn test_record_score_by_founder() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 0, 0);

    start_cheat_caller_address(test_address(), FOUNDER());
    start_cheat_block_timestamp(test_address(), 50);
    state.guild.record_score(0, 100);

    let score = guild_storage(@state).guild_scores.read(0);
    assert!(score.points == 100);
    assert!(score.last_updated == 50);
}

#[test]
fn test_record_score_accumulates() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 0, 0);

    start_cheat_caller_address(test_address(), FOUNDER());
    start_cheat_block_timestamp(test_address(), 50);
    state.guild.record_score(0, 100);
    start_cheat_block_timestamp(test_address(), 60);
    state.guild.record_score(0, 250);

    let score = guild_storage(@state).guild_scores.read(0);
    assert!(score.points == 350);
    assert!(score.last_updated == 60);
}

#[test]
fn test_record_score_by_scorer_role() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(scorer_role());
    state.guild.create_season('Season1', 0, 0);

    add_member(ref state, ALICE(), 1);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.record_score(0, 42);

    let score = guild_storage(@state).guild_scores.read(0);
    assert!(score.points == 42);
}

#[test]
#[should_panic]
fn test_record_score_without_permission_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(no_score_role());
    state.guild.create_season('Season1', 0, 0);

    add_member(ref state, BOB(), 1);
    start_cheat_caller_address(test_address(), BOB());
    state.guild.record_score(0, 10);
}

#[test]
#[should_panic]
fn test_record_score_non_member_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 0, 0);

    start_cheat_caller_address(test_address(), OUTSIDER());
    state.guild.record_score(0, 10);
}

#[test]
#[should_panic]
fn test_record_score_nonexistent_season_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.record_score(0, 10);
}

#[test]
#[should_panic]
fn test_record_score_finalized_season_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 0, 0);
    state.guild.finalize_season(0);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.record_score(0, 10);
}

#[test]
#[should_panic]
fn test_record_score_zero_points_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 0, 0);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.record_score(0, 0);
}

#[test]
#[should_panic]
fn test_record_score_before_season_starts_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 1000, 2000);

    start_cheat_caller_address(test_address(), FOUNDER());
    start_cheat_block_timestamp(test_address(), 500);
    state.guild.record_score(0, 10);
}

#[test]
#[should_panic]
fn test_record_score_after_season_ends_fails() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 100, 200);

    start_cheat_caller_address(test_address(), FOUNDER());
    start_cheat_block_timestamp(test_address(), 300);
    state.guild.record_score(0, 10);
}

#[test]
fn test_record_score_within_time_window() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 100, 200);

    start_cheat_caller_address(test_address(), FOUNDER());
    start_cheat_block_timestamp(test_address(), 150);
    state.guild.record_score(0, 77);

    let score = guild_storage(@state).guild_scores.read(0);
    assert!(score.points == 77);
}

#[test]
fn test_record_score_governor_bypasses_permission() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('Season1', 0, 0);
    state.guild.record_score(0, 999);

    let score = guild_storage(@state).guild_scores.read(0);
    assert!(score.points == 999);
}

// ========================================================================
// Multiple seasons independence tests
// ========================================================================

#[test]
fn test_scores_independent_across_seasons() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('S1', 0, 0);
    state.guild.create_season('S2', 0, 0);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.record_score(0, 100);
    state.guild.record_score(1, 200);

    assert!(guild_storage(@state).guild_scores.read(0).points == 100);
    assert!(guild_storage(@state).guild_scores.read(1).points == 200);
}

#[test]
fn test_finalize_one_season_allows_recording_in_another() {
    let mut state = setup_guild();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_season('S1', 0, 0);
    state.guild.create_season('S2', 0, 0);
    state.guild.finalize_season(0);

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.record_score(1, 50);

    assert!(guild_storage(@state).guild_scores.read(1).points == 50);
}

// ========================================================================
// Initial state tests
// ========================================================================

#[test]
fn test_initial_season_count_is_zero() {
    let state = setup_guild();
    assert!(guild_storage(@state).season_count.read() == 0);
}

#[test]
fn test_initial_guild_score_is_zero() {
    let state = setup_guild();
    let score = guild_storage(@state).guild_scores.read(0);
    assert!(score.points == 0);
    assert!(score.last_updated == 0);
}

// ========================================================================
// ActionType::SCORE constant tests
// ========================================================================

#[test]
fn test_score_action_bit_is_distinct() {
    assert!(ActionType::SCORE == 0x40);
    // Should not overlap with other core actions
    assert!(ActionType::SCORE & ActionType::TRANSFER == 0);
    assert!(ActionType::SCORE & ActionType::APPROVE == 0);
    assert!(ActionType::SCORE & ActionType::EXECUTE == 0);
    assert!(ActionType::SCORE & ActionType::SETTINGS == 0);
    assert!(ActionType::SCORE & ActionType::SHARE_MGMT == 0);
    assert!(ActionType::SCORE & ActionType::DISTRIBUTE == 0);
    // Should not overlap with PonziLand actions
    assert!(ActionType::SCORE & ActionType::ALL_PONZI == 0);
}

#[test]
fn test_score_included_in_all_core() {
    assert!(ActionType::ALL_CORE & ActionType::SCORE != 0);
}

#[test]
fn test_score_included_in_all() {
    assert!(ActionType::ALL & ActionType::SCORE != 0);
}
