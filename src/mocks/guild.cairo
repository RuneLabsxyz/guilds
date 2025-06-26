use starknet::ContractAddress;

#[starknet::interface]
pub trait IGuildMock<TContractState> {
    fn get_token_address(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod GuildMock {
    use guilds::guild::guild_contract::GuildComponent;
    use guilds::guild::guild_contract::GuildComponent::InternalImpl;
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl, DefaultConfig};
    use starknet::{ContractAddress, get_caller_address};

    // ERC20 Component
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;

    // Guild Component
    component!(path: GuildComponent, storage: guild, event: GuildEvent);
    #[abi(embed_v0)]
    impl GuildImpl = GuildComponent::GuildImpl<ContractState>;
    #[abi(embed_v0)]
    impl GuildMetadataImpl = GuildComponent::GuildMetadataImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        guild: GuildComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        GuildEvent: GuildComponent::Event,
        #[flat]
        ERC20Event: ERC20Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        guild_name: felt252,
        rank_name: felt252,
        token_name: ByteArray,
        token_symbol: ByteArray,
        token_supply: u256,
    ) {
        let creator = get_caller_address();

        // Initialize ERC20 token
        self.erc20.initializer(token_name, token_symbol);
        self.erc20.mint(creator, token_supply);

        // Save the token address in the guild
        self.guild.initializer(guild_name, rank_name, Option::Some(starknet::get_contract_address()));
    }
}
