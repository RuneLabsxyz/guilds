use starknet::ContractAddress;

#[starknet::interface]
pub trait IPonziLandActions<TState> {
    fn buy(
        ref self: TState,
        land_location: u16,
        token_for_sale: ContractAddress,
        sell_price: u256,
        amount_to_stake: u256,
    );
    fn sell(ref self: TState, land_location: u16);
    fn increase_price(ref self: TState, land_location: u16, new_price: u256);
    fn claim(ref self: TState, land_location: u16);
    fn increase_stake(ref self: TState, land_location: u16, amount_to_stake: u256);
    fn withdraw_stake(ref self: TState, land_location: u16);
}
