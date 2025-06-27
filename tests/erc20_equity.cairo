use core::option::Option;
use guilds::mocks::guild::GuildMock;
use guilds::tests::constants::{ALICE, BOB, CHARLIE, OWNER, TOKEN_ADDRESS};

use guilds::erc20::erc20_token::ERC20EquityComponent;
use guilds::erc20::erc20_token::IERC20Equity;
use guilds::erc20::erc20_token::ERC20EquityComponent::{ERC20EquityImpl};

use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, test_address,
};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};


type ComponentState = ERC20EquityComponent::ComponentState<GuildMock::ContractState>;

fn COMPONENT_STATE() -> ComponentState {
    ERC20EquityComponent::component_state_for_testing()
}

#[test]
fn test_erc20_init(){
    let mut state = COMPONENT_STATE();

    let token_name: ByteArray = "Test_Token";
    let token_symbol: ByteArray = "TKN";

    state.initializer(token_name, token_symbol, TOKEN_ADDRESS);

    assert(state.balance_of(ALICE) == 0, 'Initial balance mismatch');

    state.mint(ALICE, 1000);

    assert(state.balance_of(ALICE) == 1000, 'Minted balance mismatch');
}