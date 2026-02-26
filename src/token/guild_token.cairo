use core::num::traits::Zero;
use guilds::interfaces::token::IGuildToken;
use guilds::models::events;
use guilds::models::types::InactivityFlag;
use openzeppelin_governance::votes::VotesComponent;
use openzeppelin_governance::votes::VotesComponent::InternalTrait as VotesInternalTrait;
use openzeppelin_token::erc20::ERC20Component;
use openzeppelin_token::erc20::ERC20Component::InternalTrait as ERC20InternalTrait;
use openzeppelin_utils::contract_clock::ERC6372TimestampClock;
use openzeppelin_utils::nonces::NoncesComponent;
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

#[starknet::contract]
pub mod GuildToken {
    use super::*;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: VotesComponent, storage: votes, event: VotesEvent);
    component!(path: NoncesComponent, storage: nonces, event: NoncesEvent);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;

    #[abi(embed_v0)]
    impl VotesImpl = VotesComponent::VotesImpl<ContractState>;

    #[abi(embed_v0)]
    impl NoncesImpl = NoncesComponent::NoncesImpl<ContractState>;

    impl VotingUnitsImpl of VotesComponent::VotingUnitsTrait<ContractState> {
        fn get_voting_units(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.balance_of(account)
        }
    }

    impl ERC20Config of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }

    impl ERC20Hooks of ERC20Component::ERC20HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let _ = from;
            let _ = recipient;
            let _ = amount;
        }

        fn after_update(
            ref self: ERC20Component::ComponentState<ContractState>,
            from: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let mut contract = self.get_contract_mut();
            contract.votes.transfer_voting_units(from, recipient, amount);

            // Keep inactive_balance in sync with balance movements involving flagged accounts.
            // This ensures active_supply stays correct on transfer/mint/burn paths.
            if from != Zero::zero() && contract.inactivity_flags.read(from).flagged_at > 0 {
                let current_inactive = contract.inactive_balance.read();
                if amount <= current_inactive {
                    contract.inactive_balance.write(current_inactive - amount);
                } else {
                    contract.inactive_balance.write(0);
                }
            }
            if recipient != Zero::zero()
                && contract.inactivity_flags.read(recipient).flagged_at > 0 {
                contract.inactive_balance.write(contract.inactive_balance.read() + amount);
            }

            let ts = get_block_timestamp();
            if from != Zero::zero() {
                contract.last_activity.write(from, ts);
            }
            if recipient != Zero::zero() {
                contract.last_activity.write(recipient, ts);
            }
        }
    }

    impl SNIP12MetadataImpl of openzeppelin_utils::cryptography::snip12::SNIP12Metadata {
        fn name() -> felt252 {
            'GuildToken'
        }

        fn version() -> felt252 {
            '1'
        }
    }

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub erc20: ERC20Component::Storage,
        #[substorage(v0)]
        pub votes: VotesComponent::Storage,
        #[substorage(v0)]
        pub nonces: NoncesComponent::Storage,
        pub governor_address: ContractAddress,
        pub guild_address: ContractAddress,
        pub last_activity: Map<ContractAddress, u64>,
        pub inactivity_threshold: u64,
        pub inactivity_flags: Map<ContractAddress, InactivityFlag>,
        pub inactive_balance: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        VotesEvent: VotesComponent::Event,
        #[flat]
        NoncesEvent: NoncesComponent::Event,
        InactivityFlagged: events::InactivityFlagged,
        InactivityCleared: events::InactivityCleared,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        initial_supply: u256,
        initial_holder: ContractAddress,
        governor_address: ContractAddress,
        guild_address: ContractAddress,
        inactivity_threshold: u64,
    ) {
        self.erc20.initializer(name, symbol);
        self.governor_address.write(governor_address);
        self.guild_address.write(guild_address);
        self.inactivity_threshold.write(inactivity_threshold);

        if initial_supply > 0 {
            self.erc20.mint(initial_holder, initial_supply);
            self.last_activity.write(initial_holder, get_block_timestamp());
        }
    }

    #[external(v0)]
    fn wire_addresses_once(
        ref self: ContractState, governor_address: ContractAddress, guild_address: ContractAddress,
    ) {
        assert!(self.governor_address.read() == Zero::zero(), "{}", 'Governor already set');
        assert!(self.guild_address.read() == Zero::zero(), "{}", 'Guild already set');
        self.governor_address.write(governor_address);
        self.guild_address.write(guild_address);
    }

    #[abi(embed_v0)]
    impl GuildTokenImpl of IGuildToken<ContractState> {
        fn ping(ref self: ContractState) {
            let caller = get_caller_address();
            self.last_activity.write(caller, get_block_timestamp());
        }

        fn get_last_activity(self: @ContractState, account: ContractAddress) -> u64 {
            self.last_activity.read(account)
        }

        fn get_inactivity_threshold(self: @ContractState) -> u64 {
            self.inactivity_threshold.read()
        }

        fn flag_inactive(ref self: ContractState, account: ContractAddress) {
            let last = self.last_activity.read(account);
            let now = get_block_timestamp();
            let threshold = self.inactivity_threshold.read();

            assert!(last > 0, "Account has no activity record");
            assert!(now - last > threshold, "Account is still active");

            let existing = self.inactivity_flags.read(account);
            assert!(existing.flagged_at == 0, "Already flagged");

            let flag = InactivityFlag { flagged_at: now, flagged_by: get_caller_address() };
            self.inactivity_flags.write(account, flag);

            let balance = self.erc20.balance_of(account);
            self.inactive_balance.write(self.inactive_balance.read() + balance);

            self.emit(events::InactivityFlagged { account, flagged_by: get_caller_address() });
        }

        fn clear_inactivity_flag(ref self: ContractState) {
            let caller = get_caller_address();
            let flag = self.inactivity_flags.read(caller);
            assert!(flag.flagged_at > 0, "Not flagged");

            let balance = self.erc20.balance_of(caller);
            let current_inactive = self.inactive_balance.read();
            if balance <= current_inactive {
                self.inactive_balance.write(current_inactive - balance);
            } else {
                self.inactive_balance.write(0);
            }

            self
                .inactivity_flags
                .write(caller, InactivityFlag { flagged_at: 0, flagged_by: Zero::zero() });

            self.last_activity.write(caller, get_block_timestamp());

            self.emit(events::InactivityCleared { account: caller });
        }

        fn is_flagged_inactive(self: @ContractState, account: ContractAddress) -> bool {
            self.inactivity_flags.read(account).flagged_at > 0
        }

        fn get_inactivity_flag(self: @ContractState, account: ContractAddress) -> InactivityFlag {
            self.inactivity_flags.read(account)
        }

        fn active_supply(self: @ContractState) -> u256 {
            self.erc20.total_supply() - self.inactive_balance.read()
        }

        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            assert!(
                caller == self.governor_address.read() || caller == self.guild_address.read(),
                "Only governor or guild can mint",
            );
            self.erc20.mint(recipient, amount);
            self.last_activity.write(recipient, get_block_timestamp());
        }

        fn burn(ref self: ContractState, account: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            assert!(
                caller == self.governor_address.read() || caller == self.guild_address.read(),
                "Only governor or guild can burn",
            );
            self.erc20.burn(account, amount);
        }

        fn get_guild_address(self: @ContractState) -> ContractAddress {
            self.guild_address.read()
        }
    }

    #[external(v0)]
    fn set_governor_address(ref self: ContractState, new_governor: ContractAddress) {
        let caller = get_caller_address();
        assert!(caller == self.governor_address.read(), "Only governor");
        self.governor_address.write(new_governor);
    }

    #[external(v0)]
    fn set_guild_address(ref self: ContractState, new_guild: ContractAddress) {
        let caller = get_caller_address();
        assert!(caller == self.governor_address.read(), "Only governor");
        self.guild_address.write(new_guild);
    }
}
