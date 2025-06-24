use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::{GuildMetadataImpl, InternalImpl};
use guilds::guild::interface::IGuild;
use guilds::mocks::guild::GuildMock;
use guilds::tests::constants::{ALICE, BOB, CHARLIE, OWNER};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, test_address,
};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};

type ComponentState = GuildComponent::ComponentState<GuildMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    GuildComponent::component_state_for_testing()
}


#[test]
#[should_panic(expected: "Only owner can create ranks")]
fn test_create_rank_and_permissions() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);

    // Only owner can create a rank
    state.create_rank(2, true, false, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;
    let rank = state.ranks.read(rank_id);
    assert(rank.rank_name == 2, 'Rank name mismatch');
    assert(rank.can_invite == true, 'can_invite mismatch');
    assert(rank.can_kick == false, 'can_kick mismatch');
    assert(rank.promote == 2, 'promote mismatch');
    assert(rank.can_be_kicked == true, 'can_be_kicked mismatch');

    // Non-owner cannot create a rank
    start_cheat_caller_address(test_address(), BOB);

    state.create_rank(3, false, false, 0, false);
}

#[test]
#[should_panic(expected: "Only owner can change rank permissions")]
fn test_change_rank_permissions() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, false, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;

    // Change permissions as owner
    state.change_rank_permissions(rank_id, false, true, 1, false);
    let rank = state.ranks.read(rank_id);
    assert(rank.can_invite == false, 'can_invite should be false');
    assert(rank.can_kick == true, 'can_kick should be true');
    assert(rank.promote == 1, 'promote should be 1');
    assert(rank.can_be_kicked == false, 'can_be_kicked should be false');

    // Non-owner cannot change permissions
    start_cheat_caller_address(test_address(), CHARLIE);
    state.change_rank_permissions(rank_id, true, true, 2, true);
}

#[test]
#[should_panic(expected: "Cannot delete the creator's rank")]
fn test_delete_rank() {
    let mut state = COMPONENT_STATE();
    let guild_name: felt252 = 1234;
    let rank_name: felt252 = 1;
    state.initializer(guild_name, rank_name);
    state.create_rank(2, true, false, 2, true);
    let rank_id = state.rank_count.read() - 1_u8;

    // Only owner can delete rank
    state.delete_rank(rank_id);
}

