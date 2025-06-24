use core::num::traits::{Bounded, Zero};
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{ContractAddress, get_caller_address};

#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Member {
    pub addr: ContractAddress,
    pub rank_id: u8, // Rank ID of the member
    pub is_creator: bool,
}

#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
pub struct Rank {
    pub rank_name: felt252,
    pub can_invite: bool,
    pub can_kick: bool,
    pub promote: u8, // 0 false, 1 upto 1 rank under, 2 upto 2 ranks under, etc.
    pub can_be_kicked: bool // if false, this rank cannot be kicked or demoted by anyone. Vote required
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
        pub ranks: Map<u8, Rank>, // Maps rank ID to Rank
        pub rank_count: u8 // Total number of ranks in the guild
    }

    // Component external logic

    #[embeddable_as(GuildImpl)]
    impl Guild<
        TContractState, +HasComponent<TContractState>,
    > of interface::IGuild<ComponentState<TContractState>> {
        fn invite_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            let caller = get_caller_address();

            // Owner can always invite
            if caller != self.owner.read() {
                // Check if caller is a member
                let caller_member = self.members.read(caller);
                assert!(caller_member.addr != Zero::zero(), "Caller is not a guild member");
                // Get caller's rank
                let caller_rank = self.ranks.read(caller_member.rank_id);
                assert!(caller_rank.can_invite, "Caller does not have permission to invite");
            }
            assert!(
                self.members.read(member).addr == Zero::zero(),
                "Member already exists in the guild",
            );

            let new_member = Member {
                addr: member, rank_id: self.rank_count.read(), is_creator: false,
            };
            self.members.write(member, new_member);
        }
        fn kick_member(ref self: ComponentState<TContractState>, member: ContractAddress) {
            let caller = get_caller_address();

            // Owner can always kick
            if caller != self.owner.read() {
                // Check if caller is a member
                let caller_member = self.members.read(caller);
                assert!(caller_member.addr != Zero::zero(), "Caller is not a guild member");
                // Get caller's rank
                let caller_rank = self.ranks.read(caller_member.rank_id);
                assert!(caller_rank.can_kick, "Caller does not have permission to kick");
            }
            // Check if the member is in the guild
            let target_member = self.members.read(member);
            assert!(target_member.addr != Zero::zero(), "Member does not exist in the guild");
            // Check if the target member can be kicked
            let target_rank = self.ranks.read(target_member.rank_id);
            assert!(target_rank.can_be_kicked, "Target member cannot be kicked");

            // Remove by writing default value
            self
                .members
                .write(member, Member { addr: Zero::zero(), rank_id: 0, is_creator: false });
        }

        /// Create a new rank with specified permissions and name.
        fn create_rank(
            ref self: ComponentState<TContractState>,
            rank_name: felt252,
            can_invite: bool,
            can_kick: bool,
            promote: u8,
            can_be_kicked: bool,
        ) {
            let caller = get_caller_address();
            assert!(caller == self.owner.read(), "Only owner can create ranks");
            let rank_id = self.rank_count.read();
            let new_rank = Rank {
                rank_name: rank_name,
                can_invite: can_invite,
                can_kick: can_kick,
                promote: promote,
                can_be_kicked: can_be_kicked,
            };
            self.ranks.write(rank_id, new_rank);
            self.rank_count.write(rank_id + 1_u8);
        }

        /// Delete a rank by its ID.
        fn delete_rank(ref self: ComponentState<TContractState>, rank_id: u8) {
            let caller = get_caller_address();
            assert!(caller == self.owner.read(), "Only owner can delete ranks");
            // Prevent deleting the creator's rank (rank 0)
            assert!(rank_id != 0, "Cannot delete the creator's rank");
            // Remove the rank by writing a default value
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

        /// Change the permissions of a rank by its ID.
        fn change_rank_permissions(
            ref self: ComponentState<TContractState>,
            rank_id: u8,
            can_invite: bool,
            can_kick: bool,
            promote: u8,
            can_be_kicked: bool,
        ) {
            let caller = get_caller_address();
            assert!(caller == self.owner.read(), "Only owner can change rank permissions");
            let mut rank = self.ranks.read(rank_id);
            rank.can_invite = can_invite;
            rank.can_kick = can_kick;
            rank.promote = promote;
            rank.can_be_kicked = can_be_kicked;
            self.ranks.write(rank_id, rank);
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
            5
        }
    }

    //
    // Internal
    //

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
                rank_name: rank_name,
                can_invite: true,
                can_kick: true,
                promote: 1, // can promote upto 1 rank under
                can_be_kicked: false,
            };
            self.ranks.write(0, rank); // Rank 0 is the creator's rank
            self.members.write(caller, creator);
        }
    }
}
