use starknet::ContractAddress;

#[starknet::interface]
pub trait IGovernanceWrap<TContractState> {
    fn initializer(ref self: TContractState);
}

#[starknet::component]
pub mod GovernanceWrapComponent {
    use openzeppelin_governance::governor::GovernorComponent::{
        InternalExtendedImpl as GovernorInternalExtendedImpl, InternalImpl as GovernorInternalImpl,
    };
    use openzeppelin_governance::governor::{DefaultConfig, GovernorComponent};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalImpl as SRC5InternalImpl;
    use starknet::ContractAddress;

    #[storage]
    pub struct Storage {}

    #[embeddable_as(GovernanceWrapImpl)]
    impl GovernanceWrap<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Governor: GovernorComponent::HasComponent<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
    > of super::IGovernanceWrap<ComponentState<TContractState>> {
        fn initializer(ref self: ComponentState<TContractState>) {
            let mut governor = get_dep_component_mut!(ref self, Governor);
            governor.initializer();
        }
    }
}
