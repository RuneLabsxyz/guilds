#[starknet::contract]
pub mod GuildGovernor {
    use openzeppelin_governance::governor::GovernorComponent;
    use openzeppelin_governance::governor::GovernorComponent::InternalTrait as GovernorInternalTrait;
    use openzeppelin_governance::governor::extensions::governor_core_execution::GovernorCoreExecutionComponent;
    use openzeppelin_governance::governor::extensions::governor_counting_simple::GovernorCountingSimpleComponent;
    use openzeppelin_governance::governor::extensions::governor_settings::GovernorSettingsComponent;
    use openzeppelin_governance::governor::extensions::governor_settings::GovernorSettingsComponent::InternalTrait as GovernorSettingsInternalTrait;
    use openzeppelin_governance::governor::extensions::governor_votes_quorum_fraction::GovernorVotesQuorumFractionComponent;
    use openzeppelin_governance::governor::extensions::governor_votes_quorum_fraction::GovernorVotesQuorumFractionComponent::InternalTrait as GovernorVotesInternalTrait;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    component!(path: GovernorComponent, storage: governor, event: GovernorEvent);
    component!(
        path: GovernorSettingsComponent, storage: governor_settings, event: GovernorSettingsEvent,
    );
    component!(
        path: GovernorCountingSimpleComponent,
        storage: governor_counting,
        event: GovernorCountingEvent,
    );
    component!(
        path: GovernorVotesQuorumFractionComponent,
        storage: governor_votes,
        event: GovernorVotesEvent,
    );
    component!(
        path: GovernorCoreExecutionComponent,
        storage: governor_execution,
        event: GovernorExecutionEvent,
    );
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // Wire extension traits to their implementations.
    impl GovernorSettingsImpl = GovernorSettingsComponent::GovernorSettings<ContractState>;
    impl GovernorCountingImpl = GovernorCountingSimpleComponent::GovernorCounting<ContractState>;
    impl GovernorVotesImpl = GovernorVotesQuorumFractionComponent::GovernorVotes<ContractState>;
    impl GovernorQuorumImpl = GovernorVotesQuorumFractionComponent::GovernorQuorum<ContractState>;
    impl GovernorExecutionImpl = GovernorCoreExecutionComponent::GovernorExecution<ContractState>;

    #[abi(embed_v0)]
    impl GovernorImpl = GovernorComponent::GovernorImpl<ContractState>;

    #[abi(embed_v0)]
    impl GovernorSettingsAdminImpl =
        GovernorSettingsComponent::GovernorSettingsAdminImpl<ContractState>;

    #[abi(embed_v0)]
    impl QuorumFractionImpl =
        GovernorVotesQuorumFractionComponent::QuorumFractionImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    impl GovernorConfig of GovernorComponent::ImmutableConfig {
        fn DEFAULT_PARAMS() -> Span<felt252> {
            array![].span()
        }
    }

    impl SNIP12MetadataImpl of openzeppelin_utils::cryptography::snip12::SNIP12Metadata {
        fn name() -> felt252 {
            'GuildGovernor'
        }

        fn version() -> felt252 {
            '1'
        }
    }

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub governor: GovernorComponent::Storage,
        #[substorage(v0)]
        pub governor_settings: GovernorSettingsComponent::Storage,
        #[substorage(v0)]
        pub governor_counting: GovernorCountingSimpleComponent::Storage,
        #[substorage(v0)]
        pub governor_votes: GovernorVotesQuorumFractionComponent::Storage,
        #[substorage(v0)]
        pub governor_execution: GovernorCoreExecutionComponent::Storage,
        #[substorage(v0)]
        pub src5: SRC5Component::Storage,
        pub guild_address: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        GovernorEvent: GovernorComponent::Event,
        #[flat]
        GovernorSettingsEvent: GovernorSettingsComponent::Event,
        #[flat]
        GovernorCountingEvent: GovernorCountingSimpleComponent::Event,
        #[flat]
        GovernorVotesEvent: GovernorVotesQuorumFractionComponent::Event,
        #[flat]
        GovernorExecutionEvent: GovernorCoreExecutionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        token_address: ContractAddress,
        voting_delay: u64,
        voting_period: u64,
        proposal_threshold: u256,
        quorum_numerator: u256,
        guild_address: ContractAddress,
    ) {
        self.governor.initializer();
        self.governor_settings.initializer(voting_delay, voting_period, proposal_threshold);
        self.governor_votes.initializer(token_address, quorum_numerator);
        self.guild_address.write(guild_address);
    }

    #[external(v0)]
    fn get_guild_address(self: @ContractState) -> ContractAddress {
        self.guild_address.read()
    }
}
