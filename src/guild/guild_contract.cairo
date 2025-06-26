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
        pub pending_invites: Map<ContractAddress, u8>,
    }

    #[embeddable_as(GuildImpl)]
    impl Guild<
        TContractState, +HasComponent<TContractState>,
    > of interface::IGuild<ComponentState<TContractState>> {
        fn invite_member(
            ref self: ComponentState<TContractState>, member: ContractAddress, rank_id: Option<u8>,
        ) {
            self._only_inviter();
            self._validate_not_member(member);
            let inviter_rank_id = self._get_member_rank_id();
            let target_rank_id = self._resolve_target_rank_id(rank_id);
            self._validate_rank_higher(inviter_rank_id, target_rank_id);
            self._add_pending_invite(member, target_rank_id);
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

        /// Accept an invite to join the guild (must be called by the invited address)
        fn accept_invite(ref self: ComponentState<TContractState>) {
            let caller = get_caller_address();
            self._validate_pending_invite(caller);
            let rank_id = self.pending_invites.read(caller);
            self._add_member_with_rank(caller, rank_id);
            self._clear_pending_invite(caller);
        }

        fn promote_member(ref self: ComponentState<TContractState>, member: ContractAddress, rank_id: u8) {
            let caller = get_caller_address();
            let caller_rank_id = self._get_member_rank_id();
            self._validate_member(caller);
            self._validate_member(member);
            self._validate_rank_higher(caller_rank_id, rank_id);
            self._promote_member(member, rank_id);
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

        /// Internal: Add a member to the guild with a specific rank
        fn _add_member_with_rank(
            ref self: ComponentState<TContractState>, member: ContractAddress, rank_id: u8,
        ) {
            let new_member = Member { addr: member, rank_id, is_creator: false };
            self.members.write(member, new_member);
        }

        /// Internal: Validate that a rank exists
        fn _validate_rank_exists(self: @ComponentState<TContractState>, rank_id: u8) {
            let rank = self.ranks.read(rank_id);
            assert!(rank.rank_name != 0, "Rank does not exist");
        }

        /// Internal: Validate member's rank is higher than the target's
        fn _validate_rank_higher(
            self: @ComponentState<TContractState>, member_rank_id: u8, target_rank_id: u8,
        ) {
            assert!(member_rank_id < target_rank_id, "Can only promote to a lower rank");
        }

        /// Internal: Add a member to the guild (default to lowest rank, for backward compatibility)
        fn _add_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            let rank_id = self.rank_count.read() - 1;
            self._add_member_with_rank(member, rank_id);
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

            let target_member = self.members.read(target);
            let target_rank = self.ranks.read(target_member.rank_id);
            assert!(target_rank.can_be_kicked, "Target member cannot be kicked");

            // Prevent kicking same or higher rank (lower rank_id = higher rank)
            assert!(
                member.rank_id < target_member.rank_id,
                "Cannot kick member with same or higher rank",
            );
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

        /// Internal: Get the member's rank id (owner is always rank 0)
        fn _get_member_rank_id(self: @ComponentState<TContractState>) -> u8 {
            let member = get_caller_address();
            if member == self.owner.read() {
                0_u8
            } else {
                let member_data = self.members.read(member);
                member_data.rank_id
            }
        }

        /// Internal: Resolve the target rank id from Option<u8>, defaulting to lowest
        fn _resolve_target_rank_id(
            self: @ComponentState<TContractState>, rank_id: Option<u8>,
        ) -> u8 {
            match rank_id {
                Option::Some(id) => {
                    self._validate_rank_exists(id);
                    id
                },
                Option::None => self.rank_count.read() - 1_u8,
            }
        }

        /// Internal: Add a pending invite
        fn _add_pending_invite(
            ref self: ComponentState<TContractState>, member: ContractAddress, rank_id: u8,
        ) {
            self.pending_invites.write(member, rank_id);
        }

        /// Internal: Validate that an address has a pending invite
        fn _validate_pending_invite(
            self: @ComponentState<TContractState>, member: ContractAddress,
        ) {
            let rank_id = self.pending_invites.read(member);
            assert!(
                rank_id != 0_u8 || self.rank_count.read() == 1_u8,
                "No pending invite for this address",
            );
        }

        /// Internal: Clear a pending invite
        fn _clear_pending_invite(
            ref self: ComponentState<TContractState>, member: ContractAddress,
        ) {
            self.pending_invites.write(member, 0_u8);
        }

        /// Internal: Promote a member to a new rank
        fn _promote_member(
            ref self: ComponentState<TContractState>, member: ContractAddress, rank_id: u8,
        ) {
            self._validate_member(member);
            self._validate_rank_exists(rank_id);
            let mut member_data = self.members.read(member);
            member_data.rank_id = rank_id;
            self.members.write(member, member_data);
        }
    }
}
