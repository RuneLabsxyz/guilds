use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{ContractAddress, get_caller_address};

#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Member {
    addr: ContractAddress,
    is_creator: bool,
}

#[starknet::component]
pub mod GuildComponent {
    use crate::guild::interface;
    use super::*;


    #[storage]
    pub struct Storage {
        pub guild_name: felt252,
        pub owner: ContractAddress,
        pub members: Map<ContractAddress, Member>,
    }

    // Component external logic
    #[embeddable_as(GuildMetadataImpl)]
    impl GuildMetaData<
        TContractState, +HasComponent<TContractState>,
    > of interface::IGuildMetadata<ComponentState<TContractState>> {
        fn get_guild_name(self: @ComponentState<TContractState>) -> felt252 {
            self.guild_name.read()
        }

        fn get_owner(self: @ComponentState<TContractState>) -> ContractAddress {
            self.owner.read()
        }

        fn max_rank(self: @ComponentState<TContractState>) -> u8 {
            5
        }
    }

    //
    // Internal
    //

    #[generate_trait]
    pub impl InternalImpl<TContractState> of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, guild_name: felt252) {
            let caller = get_caller_address();
            self.guild_name.write(guild_name);
            self.owner.write(caller);
            let creator = Member { addr: caller, is_creator: true };
            self.members.write(caller, creator);
        }
    }
}
