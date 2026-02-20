use core::serde::Serde;
use guilds::interfaces::guild::{
    IGuildDispatcher, IGuildDispatcherTrait, IGuildViewDispatcher, IGuildViewDispatcherTrait,
};
use guilds::models::constants::ActionType;
use guilds::models::types::Role;
use guilds::tests::constants::AsAddressTrait;
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address};
use starknet::{ContractAddress, SyscallResultTrait, syscalls};

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

fn RECIPIENT() -> ContractAddress {
    0x555.as_address()
}

fn SPENDER() -> ContractAddress {
    0x666.as_address()
}

fn OTHER() -> ContractAddress {
    0x777.as_address()
}

fn TOKEN_GOVERNOR() -> ContractAddress {
    0x888.as_address()
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

fn member_role(actions: u32, spending_limit: u256) -> Role {
    Role {
        name: 'member',
        can_invite: false,
        can_kick: false,
        can_promote_depth: 0,
        can_be_kicked: true,
        allowed_actions: actions,
        spending_limit,
        payout_weight: 100,
    }
}

fn deploy_guild() -> (ContractAddress, IGuildDispatcher, IGuildViewDispatcher) {
    let contract = declare("Guild").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    Serde::serialize(@'TreasuryGuild', ref calldata);
    Serde::serialize(@'TRSY', ref calldata);
    Serde::serialize(@0x999.as_address(), ref calldata);
    Serde::serialize(@GOVERNOR(), ref calldata);
    Serde::serialize(@FOUNDER(), ref calldata);
    Serde::serialize(@founder_role(), ref calldata);

    let (address, _) = contract.deploy(@calldata).unwrap();
    (
        address,
        IGuildDispatcher { contract_address: address },
        IGuildViewDispatcher { contract_address: address },
    )
}

fn deploy_token(guild_address: ContractAddress) -> (ContractAddress, IERC20Dispatcher) {
    let contract = declare("GuildToken").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    let name: ByteArray = "GuildToken";
    let symbol: ByteArray = "GT";
    Serde::<ByteArray>::serialize(@name, ref calldata);
    Serde::<ByteArray>::serialize(@symbol, ref calldata);
    Serde::serialize(@1_000_000_000_000_000_000_000_u256, ref calldata);
    Serde::serialize(@FOUNDER(), ref calldata);
    Serde::serialize(@TOKEN_GOVERNOR(), ref calldata);
    Serde::serialize(@guild_address, ref calldata);
    Serde::serialize(@7_776_000_u64, ref calldata);

    let (address, _) = contract.deploy(@calldata).unwrap();
    (address, IERC20Dispatcher { contract_address: address })
}

fn deploy_ponziland() -> ContractAddress {
    let contract = declare("PonziLandMock").unwrap().contract_class();
    let calldata: Array<felt252> = array![];
    let (address, _) = contract.deploy(@calldata).unwrap();
    address
}

fn ponzi_u32(address: ContractAddress, selector: felt252) -> u32 {
    let mut ret = syscalls::call_contract_syscall(address, selector, array![].span())
        .unwrap_syscall();
    Serde::deserialize(ref ret).unwrap()
}

fn ponzi_u16(address: ContractAddress, selector: felt252) -> u16 {
    let mut ret = syscalls::call_contract_syscall(address, selector, array![].span())
        .unwrap_syscall();
    Serde::deserialize(ref ret).unwrap()
}

fn fund_guild(
    token_address: ContractAddress,
    token: IERC20Dispatcher,
    guild_address: ContractAddress,
    amount: u256,
) {
    start_cheat_caller_address(token_address, FOUNDER());
    token.transfer(guild_address, amount);
}

fn create_member_and_join(
    guild_address: ContractAddress, guild: IGuildDispatcher, member: ContractAddress, role: Role,
) {
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.create_role(role);
    guild.invite_member(member, 1, 0);
    start_cheat_caller_address(guild_address, member);
    guild.accept_invite();
}

fn register_ponziland_plugin(
    guild_address: ContractAddress, guild: IGuildDispatcher, target: ContractAddress,
) {
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', target, 8, 6);
}

#[test]
fn test_execute_transfer_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    fund_guild(token_address, token, guild_address, 1_000);
    create_member_and_join(guild_address, guild, ALICE(), member_role(ActionType::TRANSFER, 2_000));

    start_cheat_caller_address(guild_address, ALICE());
    guild
        .execute_core_action(
            ActionType::TRANSFER, RECIPIENT(), token_address, 500, array![].span(),
        );

    assert!(token.balance_of(RECIPIENT()) == 500);
}

#[test]
#[should_panic]
fn test_execute_transfer_fails_no_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    fund_guild(token_address, token, guild_address, 1_000);
    create_member_and_join(guild_address, guild, ALICE(), member_role(0, 2_000));

    start_cheat_caller_address(guild_address, ALICE());
    guild
        .execute_core_action(
            ActionType::TRANSFER, RECIPIENT(), token_address, 500, array![].span(),
        );
}

#[test]
#[should_panic]
fn test_execute_transfer_fails_exceeds_spending_limit() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    fund_guild(token_address, token, guild_address, 1_000);
    create_member_and_join(guild_address, guild, ALICE(), member_role(ActionType::TRANSFER, 300));

    start_cheat_caller_address(guild_address, ALICE());
    guild
        .execute_core_action(
            ActionType::TRANSFER, RECIPIENT(), token_address, 500, array![].span(),
        );
}

#[test]
fn test_execute_approve_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    create_member_and_join(guild_address, guild, ALICE(), member_role(ActionType::APPROVE, 2_000));

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_core_action(ActionType::APPROVE, SPENDER(), token_address, 700, array![].span());

    assert!(token.allowance(guild_address, SPENDER()) == 700);
}

#[test]
#[should_panic]
fn test_execute_approve_fails_no_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, _) = deploy_token(guild_address);
    create_member_and_join(guild_address, guild, ALICE(), member_role(ActionType::TRANSFER, 2_000));

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_core_action(ActionType::APPROVE, SPENDER(), token_address, 700, array![].span());
}

#[test]
#[should_panic]
fn test_execute_action_fails_non_member() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, _) = deploy_token(guild_address);
    start_cheat_caller_address(guild_address, OTHER());
    guild.execute_core_action(ActionType::TRANSFER, RECIPIENT(), token_address, 1, array![].span());
}

#[test]
fn test_execute_action_governor_bypasses() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    fund_guild(token_address, token, guild_address, 1_000);

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild
        .execute_core_action(
            ActionType::TRANSFER, RECIPIENT(), token_address, 900, array![].span(),
        );
    assert!(token.balance_of(RECIPIENT()) == 900);
}

#[test]
#[should_panic]
fn test_execute_action_fails_dissolved() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    fund_guild(token_address, token, guild_address, 1_000);

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.dissolve();

    start_cheat_caller_address(guild_address, FOUNDER());
    guild.execute_core_action(ActionType::TRANSFER, RECIPIENT(), token_address, 1, array![].span());
}

#[test]
#[should_panic]
fn test_execute_transfer_fails_zero_target() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, token) = deploy_token(guild_address);
    fund_guild(token_address, token, guild_address, 1_000);

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild
        .execute_core_action(
            ActionType::TRANSFER,
            starknet::contract_address_const::<0>(),
            token_address,
            1,
            array![].span(),
        );
}

#[test]
#[should_panic]
fn test_execute_transfer_fails_zero_token() {
    let (guild_address, guild, _) = deploy_guild();

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild
        .execute_core_action(
            ActionType::TRANSFER,
            RECIPIENT(),
            starknet::contract_address_const::<0>(),
            1,
            array![].span(),
        );
}

#[test]
#[should_panic]
fn test_execute_approve_fails_zero_spender() {
    let (guild_address, guild, _) = deploy_guild();
    let (token_address, _) = deploy_token(guild_address);

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild
        .execute_core_action(
            ActionType::APPROVE,
            starknet::contract_address_const::<0>(),
            token_address,
            1,
            array![].span(),
        );
}

#[test]
#[should_panic]
fn test_execute_approve_fails_zero_token() {
    let (guild_address, guild, _) = deploy_guild();

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild
        .execute_core_action(
            ActionType::APPROVE,
            SPENDER(),
            starknet::contract_address_const::<0>(),
            1,
            array![].span(),
        );
}

#[test]
#[should_panic]
fn test_execute_raw_call_fails_zero_target() {
    let (guild_address, guild, _) = deploy_guild();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild
        .execute_core_action(
            ActionType::EXECUTE,
            starknet::contract_address_const::<0>(),
            OTHER(),
            0,
            array![selector!("get_call_count")].span(),
        );
}

#[test]
fn test_register_plugin_governor() {
    let (guild_address, guild, view) = deploy_guild();
    let ponzi_address = deploy_ponziland();

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', ponzi_address, 8, 6);

    let plugin = view.get_plugin('ponziland');
    assert!(plugin.target_contract == ponzi_address);
    assert!(plugin.enabled);
    assert!(plugin.action_offset == 8);
    assert!(plugin.action_count == 6);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_non_governor() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    start_cheat_caller_address(guild_address, FOUNDER());
    guild.register_plugin('ponziland', ponzi_address, 8, 6);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_dissolved() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.dissolve();
    guild.register_plugin('ponziland', ponzi_address, 8, 6);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_already_exists() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', ponzi_address, 8, 6);
    guild.register_plugin('ponziland', ponzi_address, 16, 2);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_offset_too_low() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', ponzi_address, 7, 6);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_offset_overflow() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', ponzi_address, 30, 3);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_zero_target() {
    let (guild_address, guild, _) = deploy_guild();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', starknet::contract_address_const::<0>(), 8, 6);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_zero_action_count() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', ponzi_address, 8, 0);
}

#[test]
#[should_panic]
fn test_register_plugin_fails_action_bit_collision() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    let other_plugin = deploy_ponziland();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.register_plugin('ponziland', ponzi_address, 8, 6);
    guild.register_plugin('other', other_plugin, 10, 2);
}

#[test]
fn test_toggle_plugin_governor() {
    let (guild_address, guild, view) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.toggle_plugin('ponziland', false);
    assert!(!view.get_plugin('ponziland').enabled);
}

#[test]
#[should_panic]
fn test_toggle_plugin_fails_non_governor() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);

    start_cheat_caller_address(guild_address, FOUNDER());
    guild.toggle_plugin('ponziland', false);
}

#[test]
#[should_panic]
fn test_toggle_plugin_fails_not_found() {
    let (guild_address, guild, _) = deploy_guild();
    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.toggle_plugin('ponziland', false);
}

#[test]
fn test_execute_plugin_action_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_CLAIM_YIELD, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_plugin_action('ponziland', 3, selector!("claim"), array![12].span());

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_claim_location")) == 12);
}

#[test]
#[should_panic]
fn test_execute_plugin_action_fails_no_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(guild_address, guild, ALICE(), member_role(0, 0));

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_plugin_action('ponziland', 3, selector!("claim"), array![12].span());
}

#[test]
#[should_panic]
fn test_execute_plugin_action_fails_disabled() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_CLAIM_YIELD, 0),
    );

    start_cheat_caller_address(guild_address, GOVERNOR());
    guild.toggle_plugin('ponziland', false);

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_plugin_action('ponziland', 3, selector!("claim"), array![12].span());
}

#[test]
#[should_panic]
fn test_execute_plugin_action_fails_not_found() {
    let (guild_address, guild, _) = deploy_guild();
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_CLAIM_YIELD, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_plugin_action('ponziland', 3, selector!("claim"), array![12].span());
}

#[test]
#[should_panic]
fn test_execute_plugin_action_fails_action_out_of_range() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_CLAIM_YIELD, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.execute_plugin_action('ponziland', 6, selector!("claim"), array![12].span());
}

#[test]
fn test_ponzi_buy_land_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_BUY_LAND, 500),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_buy_land(42, BOB(), 10, 100);

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_buy_location")) == 42);
}

#[test]
#[should_panic]
fn test_ponzi_buy_land_fails_no_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(guild_address, guild, ALICE(), member_role(0, 500));

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_buy_land(42, BOB(), 10, 100);
}

#[test]
#[should_panic]
fn test_ponzi_buy_land_fails_plugin_not_registered() {
    let (guild_address, guild, _) = deploy_guild();
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_BUY_LAND, 500),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_buy_land(42, BOB(), 10, 100);
}

#[test]
fn test_ponzi_set_price_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_SET_PRICE, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_set_price(7, 123);

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_set_price_location")) == 7);
}

#[test]
fn test_ponzi_claim_yield_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_CLAIM_YIELD, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_claim_yield(9);

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_claim_location")) == 9);
}

#[test]
fn test_ponzi_increase_stake_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_STAKE, 400),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_increase_stake(10, 250);

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_stake_location")) == 10);
}

#[test]
fn test_ponzi_withdraw_stake_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_UNSTAKE, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_withdraw_stake(11);

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_withdraw_location")) == 11);
}

#[test]
fn test_get_plugin_returns_config() {
    let (guild_address, guild, view) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);

    let plugin = view.get_plugin('ponziland');
    assert!(plugin.target_contract == ponzi_address);
    assert!(plugin.enabled);
    assert!(plugin.action_offset == 8);
}

#[test]
fn test_get_guild_name_returns_name() {
    let (_, _, view) = deploy_guild();
    assert!(view.get_guild_name() == 'TreasuryGuild');
}

#[test]
fn test_ponzi_sell_land_with_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_SELL_LAND, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_sell_land(15);

    assert!(ponzi_u32(ponzi_address, selector!("get_call_count")) == 1);
    assert!(ponzi_u16(ponzi_address, selector!("get_last_sell_location")) == 15);
}

#[test]
#[should_panic]
fn test_ponzi_sell_land_fails_no_permission() {
    let (guild_address, guild, _) = deploy_guild();
    let ponzi_address = deploy_ponziland();
    register_ponziland_plugin(guild_address, guild, ponzi_address);
    create_member_and_join(guild_address, guild, ALICE(), member_role(0, 500));

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_sell_land(15);
}

#[test]
#[should_panic]
fn test_ponzi_sell_land_fails_plugin_not_registered() {
    let (guild_address, guild, _) = deploy_guild();
    create_member_and_join(
        guild_address, guild, ALICE(), member_role(ActionType::PONZI_SELL_LAND, 0),
    );

    start_cheat_caller_address(guild_address, ALICE());
    guild.ponzi_sell_land(15);
}

#[test]
fn test_view_functions_return_correct_data() {
    let (guild_address, guild, view) = deploy_guild();
    create_member_and_join(guild_address, guild, ALICE(), member_role(ActionType::TRANSFER, 1000));

    assert!(view.get_guild_ticker() == 'TRSY');
    assert!(view.get_governor_address() == GOVERNOR());
    assert!(view.get_member_count() == 2);
    assert!(view.get_role_count() == 2);

    let founder = view.get_member(FOUNDER());
    assert!(founder.addr == FOUNDER());
    assert!(founder.role_id == 0);

    let alice = view.get_member(ALICE());
    assert!(alice.addr == ALICE());
    assert!(alice.role_id == 1);
}
