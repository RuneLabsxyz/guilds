use guilds::models::types::{GovernorConfig, GuildRegistryEntry};
use starknet::ContractAddress;

/// Factory for deploying guild contract sets (Guild + GuildToken + Governor).
#[starknet::interface]
pub trait IGuildFactory<TState> {
    /// Deploy a new guild. Returns (guild_address, token_address, governor_address).
    fn create_guild(
        ref self: TState,
        name: felt252,
        ticker: felt252,
        deposit_token: ContractAddress,
        deposit_amount: u256,
        initial_token_supply: u256,
        governor_config: GovernorConfig,
    ) -> (ContractAddress, ContractAddress, ContractAddress);

    /// Get guild registry entry by guild address.
    fn get_guild(self: @TState, guild_address: ContractAddress) -> GuildRegistryEntry;

    /// Check if a guild name is already taken.
    fn is_name_taken(self: @TState, name: felt252) -> bool;

    /// Check if a guild ticker is already taken.
    fn is_ticker_taken(self: @TState, ticker: felt252) -> bool;

    /// Get all registered guild addresses.
    fn get_all_guilds(self: @TState) -> Array<ContractAddress>;

    /// Get total number of registered guilds.
    fn guild_count(self: @TState) -> u32;
}
