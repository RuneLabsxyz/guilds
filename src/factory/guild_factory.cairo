use core::num::traits::Zero;
use core::serde::Serde;
use guilds::interfaces::factory::IGuildFactory;
use guilds::models::constants::ActionType;
use guilds::models::types::{GovernorConfig, GuildRegistryEntry, Role};
use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::syscalls;
use starknet::{
    ClassHash, ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
    get_contract_address,
};

#[starknet::interface]
trait IGuildWiring<TState> {
    fn set_governor_address(ref self: TState, new_governor: ContractAddress);
}

#[starknet::interface]
trait IGuildTokenWiring<TState> {
    fn set_governor_address(ref self: TState, new_governor: ContractAddress);
    fn set_guild_address(ref self: TState, new_guild: ContractAddress);
}

#[starknet::contract]
pub mod GuildFactory {
    use super::*;

    pub mod Errors {
        pub const NAME_TAKEN: felt252 = 'Name already taken';
        pub const TICKER_TAKEN: felt252 = 'Ticker already taken';
        pub const DEPOSIT_BELOW_MINIMUM: felt252 = 'Deposit below minimum';
    }

    #[storage]
    pub struct Storage {
        pub guild_class_hash: ClassHash,
        pub token_class_hash: ClassHash,
        pub governor_class_hash: ClassHash,
        pub min_deposit: u256,
        pub inactivity_threshold: u64,
        pub guilds: Map<ContractAddress, GuildRegistryEntry>,
        pub names_taken: Map<felt252, bool>,
        pub tickers_taken: Map<felt252, bool>,
        pub guild_addresses: Map<u32, ContractAddress>,
        pub guild_count: u32,
        pub deploy_nonce: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        GuildCreated: GuildCreated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct GuildCreated {
        #[key]
        pub guild_address: ContractAddress,
        pub token_address: ContractAddress,
        pub governor_address: ContractAddress,
        pub creator: ContractAddress,
        pub name: felt252,
        pub ticker: felt252,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        guild_class_hash: ClassHash,
        token_class_hash: ClassHash,
        governor_class_hash: ClassHash,
        min_deposit: u256,
        inactivity_threshold: u64,
    ) {
        self.guild_class_hash.write(guild_class_hash);
        self.token_class_hash.write(token_class_hash);
        self.governor_class_hash.write(governor_class_hash);
        self.min_deposit.write(min_deposit);
        self.inactivity_threshold.write(inactivity_threshold);
        self.deploy_nonce.write(1);
    }

    #[abi(embed_v0)]
    impl GuildFactoryImpl of IGuildFactory<ContractState> {
        fn create_guild(
            ref self: ContractState,
            name: felt252,
            ticker: felt252,
            deposit_token: ContractAddress,
            deposit_amount: u256,
            initial_token_supply: u256,
            governor_config: GovernorConfig,
        ) -> (ContractAddress, ContractAddress, ContractAddress) {
            assert!(!self.names_taken.read(name), "{}", Errors::NAME_TAKEN);
            assert!(!self.tickers_taken.read(ticker), "{}", Errors::TICKER_TAKEN);
            assert!(deposit_amount >= self.min_deposit.read(), "{}", Errors::DEPOSIT_BELOW_MINIMUM);

            let creator = get_caller_address();
            let factory_address = get_contract_address();

            let mut token_calldata: Array<felt252> = array![];
            let token_name: ByteArray = "GuildToken";
            let token_symbol: ByteArray = "GLD";
            Serde::<ByteArray>::serialize(@token_name, ref token_calldata);
            Serde::<ByteArray>::serialize(@token_symbol, ref token_calldata);
            Serde::serialize(@initial_token_supply, ref token_calldata);
            Serde::serialize(@creator, ref token_calldata);
            Serde::serialize(@factory_address, ref token_calldata);
            Serde::serialize(@Zero::zero(), ref token_calldata);
            Serde::serialize(@self.inactivity_threshold.read(), ref token_calldata);

            let token_salt = self.next_salt();
            let (token_address, _) = syscalls::deploy_syscall(
                self.token_class_hash.read(), token_salt, token_calldata.span(), false,
            )
                .unwrap_syscall();

            let mut guild_calldata: Array<felt252> = array![];
            Serde::serialize(@name, ref guild_calldata);
            Serde::serialize(@ticker, ref guild_calldata);
            Serde::serialize(@token_address, ref guild_calldata);
            Serde::serialize(@factory_address, ref guild_calldata);
            Serde::serialize(@creator, ref guild_calldata);
            Serde::serialize(@self.default_founder_role(), ref guild_calldata);

            let guild_salt = self.next_salt();
            let (guild_address, _) = syscalls::deploy_syscall(
                self.guild_class_hash.read(), guild_salt, guild_calldata.span(), false,
            )
                .unwrap_syscall();

            let mut governor_calldata: Array<felt252> = array![];
            let quorum_numerator: u256 = governor_config.quorum_bps.into();
            Serde::serialize(@token_address, ref governor_calldata);
            Serde::serialize(@governor_config.voting_delay, ref governor_calldata);
            Serde::serialize(@governor_config.voting_period, ref governor_calldata);
            Serde::serialize(@governor_config.proposal_threshold, ref governor_calldata);
            Serde::serialize(@quorum_numerator, ref governor_calldata);
            Serde::serialize(@guild_address, ref governor_calldata);

            let governor_salt = self.next_salt();
            let (governor_address, _) = syscalls::deploy_syscall(
                self.governor_class_hash.read(), governor_salt, governor_calldata.span(), false,
            )
                .unwrap_syscall();

            IGuildWiringDispatcher { contract_address: guild_address }
                .set_governor_address(governor_address);
            IGuildTokenWiringDispatcher { contract_address: token_address }
                .set_governor_address(governor_address);
            IGuildTokenWiringDispatcher { contract_address: token_address }
                .set_guild_address(guild_address);

            if deposit_amount > 0_u256 {
                IERC20Dispatcher { contract_address: deposit_token }
                    .transfer_from(creator, guild_address, deposit_amount);
            }

            let entry = GuildRegistryEntry {
                guild_address,
                token_address,
                governor_address,
                name,
                ticker,
                creator,
                created_at: get_block_timestamp(),
                is_active: true,
            };

            self.guilds.write(guild_address, entry);
            self.names_taken.write(name, true);
            self.tickers_taken.write(ticker, true);

            let count = self.guild_count.read();
            self.guild_addresses.write(count, guild_address);
            self.guild_count.write(count + 1);

            self.emit(
                GuildCreated {
                    guild_address,
                    token_address,
                    governor_address,
                    creator,
                    name,
                    ticker,
                },
            );

            (guild_address, token_address, governor_address)
        }

        fn get_guild(self: @ContractState, guild_address: ContractAddress) -> GuildRegistryEntry {
            self.guilds.read(guild_address)
        }

        fn is_name_taken(self: @ContractState, name: felt252) -> bool {
            self.names_taken.read(name)
        }

        fn is_ticker_taken(self: @ContractState, ticker: felt252) -> bool {
            self.tickers_taken.read(ticker)
        }

        fn get_all_guilds(self: @ContractState) -> Array<ContractAddress> {
            let mut out: Array<ContractAddress> = array![];
            let mut i = 0;
            let count = self.guild_count.read();
            while i < count {
                out.append(self.guild_addresses.read(i));
                i += 1;
            }
            out
        }

        fn guild_count(self: @ContractState) -> u32 {
            self.guild_count.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn default_founder_role(self: @ContractState) -> Role {
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

        fn next_salt(ref self: ContractState) -> felt252 {
            let current = self.deploy_nonce.read();
            self.deploy_nonce.write(current + 1);
            current
        }
    }
}
