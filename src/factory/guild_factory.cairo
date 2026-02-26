use core::num::traits::Zero;
use core::serde::Serde;
use guilds::interfaces::factory::IGuildFactory;
use guilds::models::constants::ActionType;
use guilds::models::types::{GovernorConfig, GuildRegistryEntry, Role};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{
    ClassHash, ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
    syscalls,
};

#[starknet::contract]
pub mod GuildFactory {
    use super::*;

    #[storage]
    pub struct Storage {
        pub guild_class_hash: ClassHash,
        pub token_class_hash: ClassHash,
        pub governor_class_hash: ClassHash,
        pub guilds: Map<ContractAddress, GuildRegistryEntry>,
        pub names_taken: Map<felt252, bool>,
        pub tickers_taken: Map<felt252, bool>,
        pub guild_list: Map<u32, ContractAddress>,
        pub guild_count: u32,
        pub inactivity_threshold: u64,
    }

    mod Errors {
        pub const NAME_TAKEN: felt252 = 'Guild name taken';
        pub const TICKER_TAKEN: felt252 = 'Guild ticker taken';
        pub const DEPLOY_FAILED: felt252 = 'Contract deploy failed';
        pub const WIRING_FAILED: felt252 = 'Post deploy wiring failed';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        guild_class_hash: ClassHash,
        token_class_hash: ClassHash,
        governor_class_hash: ClassHash,
        inactivity_threshold: u64,
    ) {
        self.guild_class_hash.write(guild_class_hash);
        self.token_class_hash.write(token_class_hash);
        self.governor_class_hash.write(governor_class_hash);
        self.inactivity_threshold.write(inactivity_threshold);
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
            let _ = deposit_token;
            let _ = deposit_amount;

            assert!(!self.names_taken.read(name), "{}", Errors::NAME_TAKEN);
            assert!(!self.tickers_taken.read(ticker), "{}", Errors::TICKER_TAKEN);

            let creator = get_caller_address();
            let unset_address: ContractAddress = Zero::zero();
            let guild_salt = name;
            let token_salt = ticker;
            let governor_salt = name + ticker;

            let mut token_calldata: Array<felt252> = array![];
            let token_name: ByteArray = "GuildToken";
            let token_symbol: ByteArray = "GLD";
            Serde::<ByteArray>::serialize(@token_name, ref token_calldata);
            Serde::<ByteArray>::serialize(@token_symbol, ref token_calldata);
            Serde::serialize(@initial_token_supply, ref token_calldata);
            Serde::serialize(@creator, ref token_calldata);
            Serde::serialize(@unset_address, ref token_calldata);
            Serde::serialize(@unset_address, ref token_calldata);
            Serde::serialize(@self.inactivity_threshold.read(), ref token_calldata);

            let (token_address, _) = syscalls::deploy_syscall(
                self.token_class_hash.read(), token_salt, token_calldata.span(), false,
            )
                .unwrap_syscall();

            let founder_role = Role {
                name: 'founder',
                can_invite: true,
                can_kick: true,
                can_promote_depth: 255,
                can_be_kicked: false,
                allowed_actions: ActionType::ALL,
                spending_limit: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
                payout_weight: 500,
            };

            let mut guild_calldata: Array<felt252> = array![];
            Serde::serialize(@name, ref guild_calldata);
            Serde::serialize(@ticker, ref guild_calldata);
            Serde::serialize(@token_address, ref guild_calldata);
            Serde::serialize(@unset_address, ref guild_calldata);
            Serde::serialize(@creator, ref guild_calldata);
            Serde::serialize(@founder_role, ref guild_calldata);

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

            let (governor_address, _) = syscalls::deploy_syscall(
                self.governor_class_hash.read(), governor_salt, governor_calldata.span(), false,
            )
                .unwrap_syscall();

            let _ = syscalls::call_contract_syscall(
                guild_address,
                selector!("wire_governor_once"),
                array![governor_address.into()].span(),
            )
                .unwrap_syscall();

            let _ = syscalls::call_contract_syscall(
                token_address,
                selector!("wire_addresses_once"),
                array![governor_address.into(), guild_address.into()].span(),
            )
                .unwrap_syscall();

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

            let idx = self.guild_count.read();
            self.guild_list.write(idx, guild_address);
            self.guild_count.write(idx + 1);

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
            let mut list = array![];
            let count = self.guild_count.read();
            let mut i = 0;
            loop {
                if i == count {
                    break;
                }
                list.append(self.guild_list.read(i));
                i = i + 1;
            }
            list
        }

        fn guild_count(self: @ContractState) -> u32 {
            self.guild_count.read()
        }
    }
}
