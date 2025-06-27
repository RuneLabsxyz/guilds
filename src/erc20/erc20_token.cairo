use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20Equity<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn initializer(ref self: TContractState, token_name: ByteArray, token_symbol: ByteArray, guild_address: ContractAddress);
    fn balance_of(ref self: TContractState, account: ContractAddress) -> u256;
}


#[starknet::component]
pub mod ERC20EquityComponent {
    use openzeppelin_token::erc20::ERC20Component::InternalImpl as ERC20Internal;
    use openzeppelin_token::erc20::{DefaultConfig, ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin_token::erc20::ERC20Component::ERC20Impl;
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerWriteAccess;

    #[storage]
    pub struct Storage {
        pub guild_address: ContractAddress,
    }

    #[embeddable_as(ERC20EquityImpl)]
    impl ERC20Equity<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Token: ERC20Component::HasComponent<TContractState>,
    > of super::IERC20Equity<ComponentState<TContractState>> {
        /// Lightweight initializer for name and symbol
        fn initializer(
            ref self: ComponentState<TContractState>,
            token_name: ByteArray,
            token_symbol: ByteArray,
            guild_address: ContractAddress
        ) {
            let mut erc20 = get_dep_component_mut!(ref self, Token);
            erc20.initializer(token_name, token_symbol);
            self.guild_address.write(guild_address);

        }

        /// Forward mint call to the ERC20 internal implementation
        fn mint(
            ref self: ComponentState<TContractState>, recipient: ContractAddress, amount: u256,
        ) {
            let mut erc20 = get_dep_component_mut!(ref self, Token);
            erc20.mint(recipient, amount);
        }

        fn balance_of(ref self: ComponentState<TContractState>, account: ContractAddress) -> u256 {
            let erc20 = get_dep_component!(@self, Token);
            let balance = erc20.balance_of(account);
            balance
        }
    }
}
