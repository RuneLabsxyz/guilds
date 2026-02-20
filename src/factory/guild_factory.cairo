/// GuildFactory — deploys Guild + GuildToken + Governor as a coordinated set
/// and maintains a registry of all guilds with name/ticker uniqueness.
#[starknet::contract]
pub mod GuildFactory {
    use core::num::traits::Zero;
    use guilds::interfaces::factory::IGuildFactory;
    use guilds::interfaces::guild::{IGuildDispatcher, IGuildDispatcherTrait};
    use guilds::interfaces::token::{IGuildTokenDispatcher, IGuildTokenDispatcherTrait};
    use guilds::models::constants::ActionType;
    use guilds::models::events;
    use guilds::models::types::{GovernorConfig, GuildRegistryEntry, Role};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess, Vec, VecTrait, MutableVecTrait,
    };
    use starknet::{
        ClassHash, ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
        syscalls::deploy_syscall,
    };

    // ====================================================================
    // Storage
    // ====================================================================

    #[storage]
    pub struct Storage {
        /// Class hash used to deploy Guild contracts.
        pub guild_class_hash: ClassHash,
        /// Class hash used to deploy GuildToken contracts.
        pub token_class_hash: ClassHash,
        /// Class hash used to deploy Governor contracts.
        pub governor_class_hash: ClassHash,
        /// Registry: guild address => entry.
        pub guilds: Map<ContractAddress, GuildRegistryEntry>,
        /// Name uniqueness: name => guild address (zero if not taken).
        pub name_registry: Map<felt252, ContractAddress>,
        /// Ticker uniqueness: ticker => guild address (zero if not taken).
        pub ticker_registry: Map<felt252, ContractAddress>,
        /// List of all guild addresses for enumeration.
        pub guild_list: Vec<ContractAddress>,
        /// Running count of guilds.
        pub count: u32,
        /// Salt counter for deterministic deploys.
        pub deploy_salt: felt252,
    }

    // ====================================================================
    // Events
    // ====================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        GuildCreated: events::GuildCreated,
    }

    // ====================================================================
    // Errors
    // ====================================================================

    pub mod Errors {
        pub const NAME_ZERO: felt252 = 'Guild name cannot be zero';
        pub const TICKER_ZERO: felt252 = 'Guild ticker cannot be zero';
        pub const NAME_TAKEN: felt252 = 'Guild name already taken';
        pub const TICKER_TAKEN: felt252 = 'Guild ticker already taken';
        pub const DEPOSIT_TOKEN_ZERO: felt252 = 'Deposit token cannot be zero';
        pub const SUPPLY_ZERO: felt252 = 'Initial supply must be > 0';
        pub const GUILD_NOT_FOUND: felt252 = 'Guild not found in registry';
        pub const CLASS_HASH_ZERO: felt252 = 'Class hash cannot be zero';
    }

    // ====================================================================
    // Constructor
    // ====================================================================

    #[constructor]
    fn constructor(
        ref self: ContractState,
        guild_class_hash: ClassHash,
        token_class_hash: ClassHash,
        governor_class_hash: ClassHash,
    ) {
        assert!(!guild_class_hash.is_zero(), "{}", Errors::CLASS_HASH_ZERO);
        assert!(!token_class_hash.is_zero(), "{}", Errors::CLASS_HASH_ZERO);
        assert!(!governor_class_hash.is_zero(), "{}", Errors::CLASS_HASH_ZERO);

        self.guild_class_hash.write(guild_class_hash);
        self.token_class_hash.write(token_class_hash);
        self.governor_class_hash.write(governor_class_hash);
    }

    // ====================================================================
    // Internal helpers
    // ====================================================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn next_salt(ref self: ContractState) -> felt252 {
            let salt = self.deploy_salt.read();
            self.deploy_salt.write(salt + 1);
            salt
        }
    }

    // ====================================================================
    // External implementation
    // ====================================================================

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
            // --- Validations ---
            assert!(name != 0, "{}", Errors::NAME_ZERO);
            assert!(ticker != 0, "{}", Errors::TICKER_ZERO);
            assert!(
                self.name_registry.read(name) == Zero::zero(), "{}", Errors::NAME_TAKEN,
            );
            assert!(
                self.ticker_registry.read(ticker) == Zero::zero(), "{}", Errors::TICKER_TAKEN,
            );
            assert!(deposit_token != Zero::zero(), "{}", Errors::DEPOSIT_TOKEN_ZERO);
            assert!(initial_token_supply > 0, "{}", Errors::SUPPLY_ZERO);

            let creator = get_caller_address();
            let now = get_block_timestamp();
            let zero_addr: ContractAddress = Zero::zero();

            // --- Step 1: Deploy GuildToken ---
            // Constructor: (name: ByteArray, symbol: ByteArray, initial_supply,
            //               initial_holder, governor_address, guild_address,
            //               inactivity_threshold)
            // Deploy with governor_address=0 and guild_address=0; wire later.
            let mut token_calldata: Array<felt252> = array![];
            let token_name: ByteArray = "GuildToken";
            let token_symbol: ByteArray = "GT";
            token_name.serialize(ref token_calldata);
            token_symbol.serialize(ref token_calldata);
            initial_token_supply.serialize(ref token_calldata);
            creator.serialize(ref token_calldata);
            zero_addr.serialize(ref token_calldata); // governor_address (set later)
            zero_addr.serialize(ref token_calldata); // guild_address (set later)
            7_776_000_u64.serialize(ref token_calldata); // inactivity_threshold: 90 days

            let token_salt = self.next_salt();
            let (token_address, _) = deploy_syscall(
                self.token_class_hash.read(), token_salt, token_calldata.span(), false,
            )
                .unwrap_syscall();

            // --- Step 2: Deploy Guild ---
            // Constructor: (guild_name, guild_ticker, token_address,
            //               governor_address, founder, founder_role)
            // Deploy with governor_address=0; wire later.
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
            name.serialize(ref guild_calldata);
            ticker.serialize(ref guild_calldata);
            token_address.serialize(ref guild_calldata);
            zero_addr.serialize(ref guild_calldata); // governor_address (set later)
            creator.serialize(ref guild_calldata);
            founder_role.serialize(ref guild_calldata);

            let guild_salt = self.next_salt();
            let (guild_address, _) = deploy_syscall(
                self.guild_class_hash.read(), guild_salt, guild_calldata.span(), false,
            )
                .unwrap_syscall();

            // --- Step 3: Deploy Governor ---
            // Constructor: (token_address, voting_delay, voting_period,
            //               proposal_threshold, quorum_numerator, guild_address)
            let mut governor_calldata: Array<felt252> = array![];
            token_address.serialize(ref governor_calldata);
            governor_config.voting_delay.serialize(ref governor_calldata);
            governor_config.voting_period.serialize(ref governor_calldata);
            governor_config.proposal_threshold.serialize(ref governor_calldata);
            // quorum_numerator: convert basis points to OZ quorum fraction
            // OZ denominator is 1000, so quorum_bps / 10 = quorum numerator
            let quorum_numerator: u256 = (governor_config.quorum_bps / 10).into();
            quorum_numerator.serialize(ref governor_calldata);
            guild_address.serialize(ref governor_calldata);

            let governor_salt = self.next_salt();
            let (governor_address, _) = deploy_syscall(
                self.governor_class_hash.read(), governor_salt, governor_calldata.span(), false,
            )
                .unwrap_syscall();

            // --- Step 4: Wire cross-references ---
            // Set governor_address on Guild (one-shot setter)
            IGuildDispatcher { contract_address: guild_address }
                .set_governor_address(governor_address);

            // Set guild_address and governor_address on GuildToken (one-shot setters)
            IGuildTokenDispatcher { contract_address: token_address }
                .set_guild_address(guild_address);
            IGuildTokenDispatcher { contract_address: token_address }
                .set_governor_address(governor_address);

            // --- Register in registry ---
            let entry = GuildRegistryEntry {
                guild_address,
                token_address,
                governor_address,
                name,
                ticker,
                creator,
                created_at: now,
                is_active: true,
            };
            self.guilds.write(guild_address, entry);
            self.name_registry.write(name, guild_address);
            self.ticker_registry.write(ticker, guild_address);
            self.guild_list.push(guild_address);
            self.count.write(self.count.read() + 1);

            // --- Emit event ---
            self
                .emit(
                    events::GuildCreated {
                        guild_address,
                        token_address,
                        governor_address,
                        name,
                        ticker,
                        creator,
                        created_at: now,
                    },
                );

            (guild_address, token_address, governor_address)
        }

        fn get_guild(
            self: @ContractState, guild_address: ContractAddress,
        ) -> GuildRegistryEntry {
            let entry = self.guilds.read(guild_address);
            assert!(entry.guild_address != Zero::zero(), "{}", Errors::GUILD_NOT_FOUND);
            entry
        }

        fn is_name_taken(self: @ContractState, name: felt252) -> bool {
            self.name_registry.read(name) != Zero::zero()
        }

        fn is_ticker_taken(self: @ContractState, ticker: felt252) -> bool {
            self.ticker_registry.read(ticker) != Zero::zero()
        }

        fn get_all_guilds(self: @ContractState) -> Array<ContractAddress> {
            let mut result: Array<ContractAddress> = array![];
            let len = self.guild_list.len();
            let mut i: u64 = 0;
            while i < len {
                result.append(self.guild_list.at(i).read());
                i += 1;
            };
            result
        }

        fn guild_count(self: @ContractState) -> u32 {
            self.count.read()
        }
    }
}
