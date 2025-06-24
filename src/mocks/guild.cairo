#[starknet::contract]
pub mod GuildMock {
    use guilds::guild::guild_contract::GuildComponent;
    use guilds::guild::guild_contract::GuildComponent::InternalImpl;

    component!(path: GuildComponent, storage: guild, event: GuildEvent);

    #[abi(embed_v0)]
    impl GuildMetadataImpl = GuildComponent::GuildMetadataImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        guild: GuildComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        GuildEvent: GuildComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, guild_name: felt252) {
        self.guild.initializer(guild_name);
    }
}
