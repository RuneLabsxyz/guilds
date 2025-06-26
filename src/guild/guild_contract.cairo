use core::array::Array;
use core::num::traits::{Bounded, Zero};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{ContractAddress, get_caller_address};

#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Member {
    pub addr: ContractAddress,
    pub rank_id: u8,
    pub is_creator: bool,
}

#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Rank {
    pub rank_name: felt252,
    pub can_invite: bool,
    pub can_kick: bool,
    pub promote: u8,
    pub can_be_kicked: bool,
}

#[starknet::component]
pub mod GuildComponent {
    use crate::guild::interface;
    use super::{*, StoragePointerReadAccess};

    #[storage]
    pub struct Storage {
        pub guild_name: felt252,
        pub owner: ContractAddress,
        pub members: Map<ContractAddress, Member>,
        pub ranks: Map<u8, Rank>,
        pub rank_count: u8,
    }

    #[embeddable_as(GuildImpl)]
    impl Guild<
        TContractState, +HasComponent<TContractState>,
    > of interface::IGuild<ComponentState<TContractState>> {
        fn invite_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            self._only_inviter();
            self._validate_not_member(member);
            self._add_member(member);
        }

        fn kick_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            self._validate_member(member);
            self._only_kicker(member);
            self._remove_member(member);
        }

        fn create_rank(
            ref self: ComponentState<TContractState>,
            rank_name: felt252,
            can_invite: bool,
            can_kick: bool,
            promote: u8,
            can_be_kicked: bool,
        ) {
            self._only_owner();
            self._create_rank(rank_name, can_invite, can_kick, promote, can_be_kicked);
        }

        fn get_rank_permissions(ref self: ComponentState<TContractState>) -> Array<Rank> {
            let mut ranks_array = ArrayTrait::new();
            let rank_count = self.rank_count.read();
            let mut i = 0_u8;
            while i != rank_count {
                let rank = self.ranks.read(i);
                ranks_array.append(rank);
                i = i + 1_u8;
            }
            ranks_array
        }

        fn delete_rank(ref self: ComponentState<TContractState>, rank_id: u8) {
            self._only_owner();
            self._delete_rank(rank_id);
        }

        fn change_rank_permissions(
            ref self: ComponentState<TContractState>,
            rank_id: u8,
            can_invite: bool,
            can_kick: bool,
            promote: u8,
            can_be_kicked: bool,
        ) {
            self._only_owner();
            self._change_rank_permissions(rank_id, can_invite, can_kick, promote, can_be_kicked);
        }
    }

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
            self.rank_count.read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<TContractState> of InternalTrait<TContractState> {
        fn initializer(
            ref self: ComponentState<TContractState>, guild_name: felt252, rank_name: felt252,
        ) {
            let caller = get_caller_address();
            self.guild_name.write(guild_name);
            self.owner.write(caller);
            let creator = Member { addr: caller, rank_id: 0, is_creator: true };
            let rank = Rank {
                rank_name, can_invite: true, can_kick: true, promote: 1, can_be_kicked: false,
            };
            self.ranks.write(0, rank);
            self.members.write(caller, creator);
            self.rank_count.write(1_u8);
        }

        /// Internal: Add a member to the guild
        fn _add_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            let rank_id = self.rank_count.read();
            let new_member = Member { addr: member, rank_id, is_creator: false };
            self.members.write(member, new_member);
        }

        /// Internal: Remove a member from the guild
        fn _remove_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            self
                .members
                .write(member, Member { addr: Zero::zero(), rank_id: 0, is_creator: false });
        }

        /// Internal: Create a new rank
        fn _create_rank(
            ref self: ComponentState<TContractState>,
            rank_name: felt252,
            can_invite: bool,
            can_kick: bool,
            promote: u8,
            can_be_kicked: bool,
        ) {
            let rank_id = self.rank_count.read();
            let new_rank = Rank { rank_name, can_invite, can_kick, promote, can_be_kicked };
            self.ranks.write(rank_id, new_rank);
            self.rank_count.write(rank_id + 1_u8);
        }

        /// Internal: Delete a rank
        fn _delete_rank(ref self: ComponentState<TContractState>, rank_id: u8) {
            assert!(rank_id != 0, "Cannot delete the creator's rank");
            self
                .ranks
                .write(
                    rank_id,
                    Rank {
                        rank_name: 0,
                        can_invite: false,
                        can_kick: false,
                        promote: 0,
                        can_be_kicked: false,
                    },
                );
        }

        /// Internal: Change rank permissions
        fn _change_rank_permissions(
            ref self: ComponentState<TContractState>,
            rank_id: u8,
            can_invite: bool,
            can_kick: bool,
            promote: u8,
            can_be_kicked: bool,
        ) {
            let mut rank = self.ranks.read(rank_id);
            rank.can_invite = can_invite;
            rank.can_kick = can_kick;
            rank.promote = promote;
            rank.can_be_kicked = can_be_kicked;
            self.ranks.write(rank_id, rank);
        }

        /// Internal: Ensure caller is the owner
        fn _only_owner(self: @ComponentState<TContractState>) {
            assert!(
                get_caller_address() == self.owner.read(), "Only owner can perform this action",
            );
        }

        /// Internal: Ensure caller can invite
        fn _only_inviter(ref self: ComponentState<TContractState>) {
            let caller = get_caller_address();
            if caller == self.owner.read() {
                return;
            }
            let member = self.members.read(caller);
            assert!(member.addr != Zero::zero(), "Caller is not a guild member");
            let rank = self.ranks.read(member.rank_id);
            assert!(rank.can_invite, "Caller does not have permission to invite");
        }


        fn _only_kicker(ref self: ComponentState<TContractState>, target: ContractAddress) {
            let caller = get_caller_address();

            assert!(caller != target, "Target member cannot be kicked");

            if caller == self.owner.read() {
                return;
            }

            let member = self.members.read(caller);
            assert!(member.addr != Zero::zero(), "Caller is not a guild member");

            let rank = self.ranks.read(member.rank_id);
            assert!(rank.can_kick, "Caller does not have permission to kick");

            let target_rank = self.ranks.read(self.members.read(target).rank_id);
            assert!(target_rank.can_be_kicked, "Target member cannot be kicked");
        }


        /// Internal: Validate that an address is not already a member
        fn _validate_not_member(self: @ComponentState<TContractState>, member: ContractAddress) {
            let member = self.members.read(member);
            assert!(member.addr == Zero::zero(), "Member already exists in the guild");
        }

        fn _validate_member(self: @ComponentState<TContractState>, member: ContractAddress) {
            let member = self.members.read(member);
            assert!(member.addr != Zero::zero(), "Target member does not exist in the guild");
        }
    }
}
