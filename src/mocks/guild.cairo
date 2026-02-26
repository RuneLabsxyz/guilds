/// Minimal mock contract for testing the v0.2 GuildComponent.
/// Only embeds the GuildComponent — no ERC20 or Governor.
#[starknet::contract]
pub mod GuildMock {
    use guilds::guild::guild_contract::GuildComponent;
    use guilds::guild::guild_contract::GuildComponent::InternalImpl;
    use guilds::models::types::Role;
    use starknet::ContractAddress;

    component!(path: GuildComponent, storage: guild, event: GuildEvent);

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub guild: GuildComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        GuildEvent: GuildComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        guild_name: felt252,
        guild_ticker: felt252,
        token_address: ContractAddress,
        governor_address: ContractAddress,
        founder: ContractAddress,
        founder_role: Role,
    ) {
        self
            .guild
            .initializer(
                guild_name, guild_ticker, token_address, governor_address, founder, founder_role,
            );
    }
}
