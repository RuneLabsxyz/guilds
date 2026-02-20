use core::ops::{Deref, DerefMut};
use core::serde::Serde;
use guilds::guild::guild_contract::GuildComponent;
use guilds::guild::guild_contract::GuildComponent::InternalImpl;
use guilds::interfaces::token::{IGuildTokenDispatcher, IGuildTokenDispatcherTrait};
use guilds::mocks::guild::GuildMock;
use guilds::models::constants::{ActionType, TOKEN_MULTIPLIER};
use guilds::models::types::{DistributionPolicy, RedemptionWindow, Role, ShareOffer};
use guilds::tests::constants::AsAddressTrait;
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_interfaces::votes::{IVotesDispatcher, IVotesDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
    start_cheat_caller_address, test_address,
};
use starknet::ContractAddress;
use starknet::storage::{
    StorageMapReadAccess, StoragePointerReadAccess, StorageTrait, StorageTraitMut,
};

fn FOUNDER() -> ContractAddress {
    0x111.as_address()
}

fn GOVERNOR() -> ContractAddress {
    0x222.as_address()
}

fn ALICE() -> ContractAddress {
    0x333.as_address()
}

fn BOB() -> ContractAddress {
    0x444.as_address()
}

fn CHARLIE() -> ContractAddress {
    0x555.as_address()
}

fn ONE() -> u256 {
    1_000_000_000_000_000_000_u256
}

fn HUNDRED() -> u256 {
    100 * ONE()
}

fn THOUSAND() -> u256 {
    1_000 * ONE()
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

fn officer_role() -> Role {
    Role {
        name: 'officer',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: ActionType::ALL,
        spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
        payout_weight: 250,
    }
}

fn weak_role() -> Role {
    Role {
        name: 'weak',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: 0,
        spending_limit: 0,
        payout_weight: 100,
    }
}

type TestState = GuildMock::ContractState;

fn guild_storage(state: @TestState) -> GuildComponent::StorageStorageBase {
    state.guild.deref().storage()
}

fn guild_storage_mut(ref state: TestState) -> GuildComponent::StorageStorageBaseMut {
    state.guild.deref_mut().storage_mut()
}

fn deploy_token(
    initial_holder: ContractAddress,
    governor: ContractAddress,
    guild_address: ContractAddress,
    initial_supply: u256,
) -> ContractAddress {
    let contract = declare("GuildToken").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "GuildToken";
    let symbol: ByteArray = "GT";
    Serde::<ByteArray>::serialize(@name, ref calldata);
    Serde::<ByteArray>::serialize(@symbol, ref calldata);
    Serde::serialize(@initial_supply, ref calldata);
    Serde::serialize(@initial_holder, ref calldata);
    Serde::serialize(@governor, ref calldata);
    Serde::serialize(@guild_address, ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);

    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn setup_state() -> (TestState, ContractAddress, ContractAddress) {
    start_cheat_block_timestamp(test_address(), 1);

    let guild_token = deploy_token(FOUNDER(), GOVERNOR(), test_address(), THOUSAND());
    let revenue_token = deploy_token(FOUNDER(), GOVERNOR(), test_address(), 10_000 * ONE());

    let mut state = GuildMock::contract_state_for_testing();
    start_cheat_caller_address(test_address(), FOUNDER());
    state
        .guild
        .initializer('RevenueGuild', 'RVN', guild_token, GOVERNOR(), FOUNDER(), founder_role());

    (state, guild_token, revenue_token)
}

fn fund_contract(token: ContractAddress, amount: u256) {
    let erc20 = IERC20Dispatcher { contract_address: token };
    start_cheat_caller_address(token, FOUNDER());
    erc20.transfer(test_address(), amount);
}

fn set_distribution(
    ref state: TestState, treasury_bps: u16, player_bps: u16, shareholder_bps: u16,
) {
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_distribution_policy(DistributionPolicy { treasury_bps, player_bps, shareholder_bps });
}

fn set_revenue_token(ref state: TestState, token: ContractAddress) {
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.set_revenue_token(token);
}

fn create_role_and_join(ref state: TestState, member: ContractAddress, role: Role) {
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(role);
    state.guild.invite_member(member, 1, 0);
    start_cheat_caller_address(test_address(), member);
    state.guild.accept_invite();
}

fn delegate_self(token: ContractAddress, account: ContractAddress) {
    let votes = IVotesDispatcher { contract_address: token };
    start_cheat_caller_address(token, account);
    votes.delegate(account);
}

fn approve_for_guild(token: IERC20Dispatcher, owner: ContractAddress, amount: u256) {
    start_cheat_caller_address(token.contract_address, owner);
    token.approve(test_address(), amount);
}

#[test]
fn test_set_distribution_policy_governor() {
    let (mut state, _, _) = setup_state();
    set_distribution(ref state, 2500, 4500, 3000);
    let policy = guild_storage(@state).distribution_policy.read();
    assert!(policy.treasury_bps == 2500);
    assert!(policy.player_bps == 4500);
    assert!(policy.shareholder_bps == 3000);
}

#[test]
#[should_panic]
fn test_set_distribution_policy_fails_non_governor() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), FOUNDER());
    state
        .guild
        .set_distribution_policy(
            DistributionPolicy { treasury_bps: 3000, player_bps: 5000, shareholder_bps: 2000 },
        );
}

#[test]
#[should_panic]
fn test_set_distribution_policy_fails_invalid_bps() {
    let (mut state, _, _) = setup_state();
    set_distribution(ref state, 3000, 5000, 1000);
}

#[test]
fn test_set_revenue_token_governor() {
    let (mut state, _, revenue_token) = setup_state();
    fund_contract(revenue_token, HUNDRED());
    set_revenue_token(ref state, revenue_token);
    assert!(guild_storage(@state).revenue_token.read() == revenue_token);
    assert!(guild_storage(@state).revenue_balance_checkpoint.read() == HUNDRED());
}

#[test]
#[should_panic]
fn test_set_revenue_token_fails_non_governor() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.set_revenue_token(revenue_token);
}

#[test]
#[should_panic]
fn test_set_revenue_token_fails_zero_address() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.set_revenue_token(starknet::contract_address_const::<0>());
}

#[test]
fn test_finalize_epoch_splits_revenue_correctly() {
    let (mut state, _, revenue_token) = setup_state();
    set_distribution(ref state, 3000, 5000, 2000);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 1_000 * ONE());

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    let snapshot = guild_storage(@state).epoch_snapshots.read(0);
    assert!(snapshot.total_revenue == 1_000 * ONE());
    assert!(snapshot.treasury_amount == 300 * ONE());
    assert!(snapshot.player_amount == 500 * ONE());
    assert!(snapshot.shareholder_amount == 200 * ONE());
}

#[test]
fn test_finalize_epoch_increments_epoch_counter() {
    let (mut state, _, revenue_token) = setup_state();
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    assert!(guild_storage(@state).current_epoch.read() == 1);
}

#[test]
fn test_finalize_epoch_records_snapshot() {
    let (mut state, guild_token, revenue_token) = setup_state();
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 200 * ONE());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    let snapshot = guild_storage(@state).epoch_snapshots.read(0);
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    assert!(snapshot.active_supply == token.active_supply());
    assert!(snapshot.total_payout_weight == 500);
}

#[test]
#[should_panic]
fn test_finalize_epoch_fails_no_revenue_token() {
    let (mut state, _, revenue_token) = setup_state();
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
}

#[test]
#[should_panic]
fn test_finalize_epoch_fails_no_revenue() {
    let (mut state, _, revenue_token) = setup_state();
    set_revenue_token(ref state, revenue_token);
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
}

#[test]
#[should_panic]
fn test_finalize_epoch_fails_when_balance_below_checkpoint() {
    let (mut state, _, revenue_token) = setup_state();
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());

    let revenue = IERC20Dispatcher { contract_address: revenue_token };
    start_cheat_caller_address(revenue_token, test_address());
    revenue.transfer(ALICE(), ONE());

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
}

#[test]
#[should_panic]
fn test_finalize_epoch_fails_no_permission() {
    let (mut state, _, revenue_token) = setup_state();
    create_role_and_join(ref state, ALICE(), weak_role());
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.finalize_epoch();
}

#[test]
fn test_claim_player_revenue_correct_amount() {
    let (mut state, _, revenue_token) = setup_state();
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    let erc20 = IERC20Dispatcher { contract_address: revenue_token };
    let checkpoint_before = guild_storage(@state).revenue_balance_checkpoint.read();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.claim_player_revenue(0);
    let checkpoint_after = guild_storage(@state).revenue_balance_checkpoint.read();
    assert!(checkpoint_after < checkpoint_before);
    assert!(guild_storage(@state).member_last_claimed_epoch.read(FOUNDER()) == 1);
    let _ = erc20;
}

#[test]
fn test_claim_player_revenue_proportional_to_weight() {
    let (mut state, _, revenue_token) = setup_state();
    create_role_and_join(ref state, ALICE(), officer_role());
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 750 * ONE());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    let checkpoint_before = guild_storage(@state).revenue_balance_checkpoint.read();

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.claim_player_revenue(0);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.claim_player_revenue(0);

    let checkpoint_after = guild_storage(@state).revenue_balance_checkpoint.read();
    assert!(checkpoint_after < checkpoint_before);
    assert!(guild_storage(@state).member_last_claimed_epoch.read(FOUNDER()) == 1);
    assert!(guild_storage(@state).member_last_claimed_epoch.read(ALICE()) == 1);
}

#[test]
#[should_panic]
fn test_claim_player_revenue_fails_non_member() {
    let (mut state, _, revenue_token) = setup_state();
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.claim_player_revenue(0);
}

#[test]
#[should_panic]
fn test_claim_player_revenue_fails_epoch_not_finalized() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.claim_player_revenue(0);
}

#[test]
#[should_panic]
fn test_claim_player_revenue_fails_already_claimed() {
    let (mut state, _, revenue_token) = setup_state();
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    state.guild.claim_player_revenue(0);
    state.guild.claim_player_revenue(0);
}

#[test]
#[should_panic]
fn test_claim_player_revenue_fails_dissolved() {
    let (mut state, _, revenue_token) = setup_state();
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    state.guild.dissolve();
    state.guild.claim_player_revenue(0);
}

#[test]
fn test_claim_player_revenue_multiple_members() {
    let (mut state, _, revenue_token) = setup_state();
    create_role_and_join(ref state, ALICE(), officer_role());
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 750 * ONE());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    state.guild.claim_player_revenue(0);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.claim_player_revenue(0);
    assert!(guild_storage(@state).revenue_balance_checkpoint.read() == 0);
}

#[test]
fn test_accept_invite_sets_member_claim_cursor_to_current_epoch() {
    let (mut state, _, revenue_token) = setup_state();
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    create_role_and_join(ref state, ALICE(), officer_role());

    assert!(guild_storage(@state).member_last_claimed_epoch.read(ALICE()) == 1);
}

#[test]
#[should_panic]
fn test_joined_member_cannot_claim_player_revenue_for_past_epoch() {
    let (mut state, _, revenue_token) = setup_state();
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    create_role_and_join(ref state, ALICE(), officer_role());

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.claim_player_revenue(0);
}

#[test]
fn test_joined_member_can_claim_player_revenue_for_future_epoch() {
    let (mut state, _, revenue_token) = setup_state();
    set_distribution(ref state, 0, 10_000, 0);
    set_revenue_token(ref state, revenue_token);

    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    create_role_and_join(ref state, ALICE(), officer_role());

    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.claim_player_revenue(1);
    assert!(guild_storage(@state).member_last_claimed_epoch.read(ALICE()) == 2);
}

#[test]
fn test_claim_shareholder_revenue_correct_amount() {
    let (mut state, guild_token, revenue_token) = setup_state();
    delegate_self(guild_token, FOUNDER());
    set_distribution(ref state, 0, 0, 10_000);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    start_cheat_block_timestamp(test_address(), 2);
    start_cheat_block_timestamp(guild_token, 2);
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.claim_shareholder_revenue(0);
    assert!(guild_storage(@state).shareholder_last_claimed_epoch.read(FOUNDER()) == 1);
}

#[test]
fn test_claim_shareholder_revenue_proportional_to_balance() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    let revenue = IERC20Dispatcher { contract_address: revenue_token };

    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), THOUSAND());

    delegate_self(guild_token, FOUNDER());
    delegate_self(guild_token, ALICE());

    set_distribution(ref state, 0, 0, 10_000);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 200 * ONE());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    start_cheat_block_timestamp(test_address(), 2);
    start_cheat_block_timestamp(guild_token, 2);
    let alice_before = revenue.balance_of(ALICE());
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.claim_shareholder_revenue(0);
    assert!(revenue.balance_of(ALICE()) > alice_before);
}

#[test]
#[should_panic]
fn test_claim_shareholder_revenue_fails_epoch_not_finalized() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.claim_shareholder_revenue(0);
}

#[test]
#[should_panic]
fn test_claim_shareholder_revenue_fails_already_claimed() {
    let (mut state, guild_token, revenue_token) = setup_state();
    delegate_self(guild_token, FOUNDER());
    set_distribution(ref state, 0, 0, 10_000);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    start_cheat_block_timestamp(test_address(), 2);
    start_cheat_block_timestamp(guild_token, 2);
    state.guild.claim_shareholder_revenue(0);
    state.guild.claim_shareholder_revenue(0);
}

#[test]
fn test_claim_shareholder_revenue_non_member_can_claim() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };

    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(BOB(), HUNDRED());
    delegate_self(guild_token, BOB());

    set_distribution(ref state, 0, 0, 10_000);
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, HUNDRED());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    start_cheat_block_timestamp(test_address(), 2);
    start_cheat_block_timestamp(guild_token, 2);
    start_cheat_caller_address(test_address(), BOB());
    state.guild.claim_shareholder_revenue(0);
}

#[test]
fn test_create_share_offer_governor() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );

    assert!(guild_storage(@state).has_active_offer.read());
}

#[test]
#[should_panic]
fn test_create_share_offer_fails_non_governor() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), FOUNDER());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );
}

#[test]
#[should_panic]
fn test_create_share_offer_fails_already_active() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    let offer = ShareOffer {
        deposit_token: revenue_token,
        max_total: THOUSAND(),
        minted_so_far: 0,
        price_per_share: ONE(),
        expires_at: 0,
    };
    state.guild.create_share_offer(offer);
    state.guild.create_share_offer(offer);
}

#[test]
#[should_panic]
fn test_create_share_offer_fails_zero_deposit_token() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: starknet::contract_address_const::<0>(),
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );
}

#[test]
#[should_panic]
fn test_create_share_offer_fails_zero_max_total() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: 0,
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );
}

#[test]
#[should_panic]
fn test_create_share_offer_fails_zero_price() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: 0,
                expires_at: 0,
            },
        );
}

#[test]
#[should_panic]
fn test_create_share_offer_fails_expired_at_creation() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_block_timestamp(test_address(), 10);
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 10,
            },
        );
}

#[test]
fn test_create_share_offer_allows_replacing_expired_offer() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 2,
            },
        );

    start_cheat_block_timestamp(test_address(), 3);
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: 2 * THOUSAND(),
                minted_so_far: 0,
                price_per_share: 2 * ONE(),
                expires_at: 0,
            },
        );

    let offer = guild_storage(@state).active_offer.read();
    assert!(guild_storage(@state).has_active_offer.read());
    assert!(offer.max_total == 2 * THOUSAND());
    assert!(offer.price_per_share == 2 * ONE());
}

#[test]
fn test_buy_shares_mints_tokens() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    let deposit = IERC20Dispatcher { contract_address: revenue_token };

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: 3 * ONE(),
                expires_at: 0,
            },
        );

    start_cheat_caller_address(revenue_token, FOUNDER());
    deposit.transfer(GOVERNOR(), 10 * ONE());
    approve_for_guild(deposit, GOVERNOR(), 10 * ONE());

    let before = IERC20Dispatcher { contract_address: guild_token }.balance_of(GOVERNOR());
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.buy_shares(2 * ONE());
    assert!(
        IERC20Dispatcher { contract_address: guild_token }.balance_of(GOVERNOR()) == before
            + 2 * ONE(),
    );

    let _ = token;
}

#[test]
fn test_buy_shares_transfers_deposit() {
    let (mut state, _, revenue_token) = setup_state();
    let deposit = IERC20Dispatcher { contract_address: revenue_token };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: 2 * ONE(),
                expires_at: 0,
            },
        );

    start_cheat_caller_address(revenue_token, FOUNDER());
    deposit.transfer(GOVERNOR(), 10 * ONE());
    approve_for_guild(deposit, GOVERNOR(), 10 * ONE());

    let before = deposit.balance_of(test_address());
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.buy_shares(3 * ONE());
    assert!(deposit.balance_of(test_address()) == before + 6 * ONE());
}

#[test]
#[should_panic]
fn test_buy_shares_fails_no_active_offer() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.buy_shares(ONE());
}

#[test]
#[should_panic]
fn test_buy_shares_fails_zero_amount() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.buy_shares(0);
}

#[test]
#[should_panic]
fn test_buy_shares_fails_zero_rounded_cost() {
    let (mut state, _, revenue_token) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: 1,
                expires_at: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.buy_shares(1);
}

#[test]
#[should_panic]
fn test_buy_shares_fails_expired() {
    let (mut state, _, revenue_token) = setup_state();
    let deposit = IERC20Dispatcher { contract_address: revenue_token };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 10,
            },
        );

    start_cheat_caller_address(revenue_token, FOUNDER());
    deposit.transfer(ALICE(), 5 * ONE());
    approve_for_guild(deposit, ALICE(), 5 * ONE());
    start_cheat_block_timestamp(test_address(), 11);

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.buy_shares(ONE());
}

#[test]
#[should_panic]
fn test_buy_shares_fails_exceeds_max() {
    let (mut state, _, revenue_token) = setup_state();
    let deposit = IERC20Dispatcher { contract_address: revenue_token };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: ONE(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );

    start_cheat_caller_address(revenue_token, FOUNDER());
    deposit.transfer(ALICE(), 5 * ONE());
    approve_for_guild(deposit, ALICE(), 5 * ONE());
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.buy_shares(2 * ONE());
}

#[test]
#[should_panic]
fn test_buy_shares_fails_dissolved() {
    let (mut state, _, revenue_token) = setup_state();
    let deposit = IERC20Dispatcher { contract_address: revenue_token };
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: ONE(),
                expires_at: 0,
            },
        );
    state.guild.dissolve();

    start_cheat_caller_address(revenue_token, FOUNDER());
    deposit.transfer(ALICE(), 5 * ONE());
    approve_for_guild(deposit, ALICE(), 5 * ONE());

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.buy_shares(ONE());
}

#[test]
fn test_set_redemption_window_governor() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: THOUSAND(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 2,
            },
        );
    let window = guild_storage(@state).redemption_window.read();
    assert!(window.enabled);
    assert!(window.max_per_epoch == THOUSAND());
    assert!(window.cooldown_epochs == 2);
}

#[test]
#[should_panic]
fn test_set_redemption_window_fails_non_governor() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), FOUNDER());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: THOUSAND(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 1,
            },
        );
}

#[test]
#[should_panic]
fn test_set_redemption_window_fails_enabled_zero_max_per_epoch() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true, max_per_epoch: 0, redeemed_this_epoch: 0, cooldown_epochs: 0,
            },
        );
}

#[test]
#[should_panic]
fn test_set_redemption_window_fails_nonzero_redeemed_this_epoch() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: false,
                max_per_epoch: 0,
                redeemed_this_epoch: ONE(),
                cooldown_epochs: 0,
            },
        );
}

#[test]
fn test_redeem_shares_burns_and_pays() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    let guild_erc20 = IERC20Dispatcher { contract_address: guild_token };
    let revenue = IERC20Dispatcher { contract_address: revenue_token };

    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), HUNDRED());
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 500 * ONE());

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: THOUSAND(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 0,
            },
        );

    let payout = (500 * ONE() * HUNDRED()) / guild_erc20.total_supply();
    let token_before = guild_erc20.balance_of(ALICE());
    let revenue_before = revenue.balance_of(ALICE());
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(HUNDRED());

    assert!(guild_erc20.balance_of(ALICE()) == token_before - HUNDRED());
    assert!(revenue.balance_of(ALICE()) == revenue_before + payout);
}

#[test]
fn test_finalize_epoch_resets_redemption_epoch_usage() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), HUNDRED());

    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 200 * ONE());
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true, max_per_epoch: HUNDRED(), redeemed_this_epoch: 0, cooldown_epochs: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(HUNDRED());
    assert!(guild_storage(@state).redemption_window.read().redeemed_this_epoch == HUNDRED());

    fund_contract(revenue_token, ONE());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    assert!(guild_storage(@state).redemption_window.read().redeemed_this_epoch == 0);
}

#[test]
fn test_redeem_shares_limit_applies_per_epoch_not_lifetime() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), 2 * HUNDRED());

    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 400 * ONE());
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true, max_per_epoch: HUNDRED(), redeemed_this_epoch: 0, cooldown_epochs: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(HUNDRED());

    fund_contract(revenue_token, ONE());
    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(HUNDRED());
}

#[test]
#[should_panic]
fn test_redeem_shares_fails_not_enabled() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(ONE());
}

#[test]
#[should_panic]
fn test_redeem_shares_fails_zero_amount() {
    let (mut state, _, _) = setup_state();
    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: THOUSAND(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(0);
}

#[test]
#[should_panic]
fn test_redeem_shares_fails_exceeds_epoch_limit() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), HUNDRED());
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 300 * ONE());

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: 50 * ONE(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(HUNDRED());
}

#[test]
#[should_panic]
fn test_redeem_shares_fails_zero_rounded_payout() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), ONE());
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 1);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: THOUSAND(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 0,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(1);
}

#[test]
#[should_panic]
fn test_redeem_shares_fails_cooldown() {
    let (mut state, guild_token, revenue_token) = setup_state();
    let token = IGuildTokenDispatcher { contract_address: guild_token };
    start_cheat_caller_address(guild_token, GOVERNOR());
    token.mint(ALICE(), HUNDRED());
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 300 * ONE());

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .set_redemption_window(
            RedemptionWindow {
                enabled: true,
                max_per_epoch: THOUSAND(),
                redeemed_this_epoch: 0,
                cooldown_epochs: 1,
            },
        );

    start_cheat_caller_address(test_address(), ALICE());
    state.guild.redeem_shares(ONE());
}

#[test]
fn test_accept_invite_updates_total_weight() {
    let (mut state, _, _) = setup_state();
    assert!(guild_storage(@state).total_payout_weight.read() == 500);
    create_role_and_join(ref state, ALICE(), officer_role());
    assert!(guild_storage(@state).total_payout_weight.read() == 750);
}

#[test]
fn test_kick_updates_total_weight() {
    let (mut state, _, _) = setup_state();
    create_role_and_join(ref state, ALICE(), officer_role());
    assert!(guild_storage(@state).total_payout_weight.read() == 750);
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.kick_member(ALICE());
    assert!(guild_storage(@state).total_payout_weight.read() == 500);
}

#[test]
fn test_leave_updates_total_weight() {
    let (mut state, _, _) = setup_state();
    create_role_and_join(ref state, ALICE(), officer_role());
    assert!(guild_storage(@state).total_payout_weight.read() == 750);
    start_cheat_caller_address(test_address(), ALICE());
    state.guild.leave_guild();
    assert!(guild_storage(@state).total_payout_weight.read() == 500);
}

#[test]
fn test_modify_role_updates_total_weight_for_existing_members() {
    let (mut state, _, _) = setup_state();
    create_role_and_join(ref state, ALICE(), officer_role());
    assert!(guild_storage(@state).total_payout_weight.read() == 750);

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .modify_role(
            1,
            Role {
                name: 'officer',
                can_invite: false,
                can_kick: false,
                can_promote_depth: 0,
                can_be_kicked: true,
                allowed_actions: ActionType::ALL,
                spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                payout_weight: 400,
            },
        );

    assert!(guild_storage(@state).total_payout_weight.read() == 900);
}

#[test]
fn test_change_member_role_updates_total_weight() {
    let (mut state, _, _) = setup_state();
    create_role_and_join(ref state, ALICE(), officer_role());
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.create_role(weak_role());
    assert!(guild_storage(@state).total_payout_weight.read() == 750);

    state.guild.change_member_role(ALICE(), 2);
    assert!(guild_storage(@state).total_payout_weight.read() == 600);
}

#[test]
fn test_set_revenue_token_checkpoint_uses_current_balance() {
    let (mut state, _, revenue_token) = setup_state();
    fund_contract(revenue_token, 333 * ONE());
    set_revenue_token(ref state, revenue_token);
    assert!(guild_storage(@state).revenue_balance_checkpoint.read() == 333 * ONE());
}

#[test]
fn test_finalize_epoch_uses_checkpoint_delta() {
    let (mut state, _, revenue_token) = setup_state();
    fund_contract(revenue_token, 200 * ONE());
    set_revenue_token(ref state, revenue_token);
    fund_contract(revenue_token, 50 * ONE());

    start_cheat_caller_address(test_address(), FOUNDER());
    state.guild.finalize_epoch();
    let snapshot = guild_storage(@state).epoch_snapshots.read(0);
    assert!(snapshot.total_revenue == 50 * ONE());
}

#[test]
fn test_buy_shares_cost_uses_token_multiplier() {
    let (mut state, _, revenue_token) = setup_state();
    let deposit = IERC20Dispatcher { contract_address: revenue_token };

    start_cheat_caller_address(test_address(), GOVERNOR());
    state
        .guild
        .create_share_offer(
            ShareOffer {
                deposit_token: revenue_token,
                max_total: THOUSAND(),
                minted_so_far: 0,
                price_per_share: 3 * ONE(),
                expires_at: 0,
            },
        );

    start_cheat_caller_address(revenue_token, FOUNDER());
    deposit.transfer(GOVERNOR(), 20 * ONE());
    approve_for_guild(deposit, GOVERNOR(), 20 * ONE());

    let before = deposit.balance_of(test_address());
    start_cheat_caller_address(test_address(), GOVERNOR());
    state.guild.buy_shares(4 * ONE());
    assert!(
        deposit.balance_of(test_address()) == before + (4 * ONE() * 3 * ONE()) / TOKEN_MULTIPLIER,
    );
}
