#[starknet::contract]
mod GuildManagement {
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess,
        StorageMapWriteAccess
    };
    use starknet::get_caller_address;

    #[starknet::interface]
    trait IGuildManagement<TContractState> {
        fn create_guild(ref self: TContractState) -> u256;
        fn invite_to_guild(ref self: TContractState, guild_id: u256, user: ContractAddress);
        fn promote(ref self: TContractState, guild_id: u256, user: ContractAddress);
        fn demote(ref self: TContractState, guild_id: u256, user: ContractAddress);
        fn kick(ref self: TContractState, guild_id: u256, user: ContractAddress);
    }

    #[derive(Serde, Drop, starknet::Store, PartialEq, Copy)]
    enum Role {
        #[default]
        None,
        Member,
        Officer,
        Creator,
    }

    #[storage]
    struct Storage {
        next_guild_id: u256,
        guild_members: Map<(u256, ContractAddress), Role>,
        guild_creator: Map<u256, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GuildCreated: GuildCreated,
        UserInvited: UserInvited,
        UserPromoted: UserPromoted,
        UserDemoted: UserDemoted,
        UserKicked: UserKicked,
    }

    #[derive(Drop, starknet::Event)]
    struct GuildCreated {
        #[key]
        guild_id: u256,
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UserInvited {
        #[key]
        guild_id: u256,
        user: ContractAddress,
        invited_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UserPromoted {
        #[key]
        guild_id: u256,
        user: ContractAddress,
        promoted_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UserDemoted {
        #[key]
        guild_id: u256,
        user: ContractAddress,
        demoted_by: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct UserKicked {
        #[key]
        guild_id: u256,
        user: ContractAddress,
        kicked_by: ContractAddress,
    }

    #[abi(embed_v0)]
    impl GuildManagementImpl of IGuildManagement<ContractState> {
        fn create_guild(ref self: ContractState) -> u256 {
            let caller = get_caller_address();
            let guild_id = self.next_guild_id.read();

            self.guild_creator.write(guild_id, caller);
            self.guild_members.write((guild_id, caller), Role::Creator);

            self.next_guild_id.write(guild_id + 1);

            self.emit(Event::GuildCreated(GuildCreated { guild_id, creator: caller }));

            guild_id
        }

        fn invite_to_guild(ref self: ContractState, guild_id: u256, user: ContractAddress) {
            let caller = get_caller_address();
            self.assert_is_creator_or_officer(guild_id, caller);

            let user_role = self.get_role(guild_id, user);
            assert(user_role == Role::None, 'User in guild');

            self.guild_members.write((guild_id, user), Role::Member);

            self.emit(Event::UserInvited(UserInvited { guild_id, user, invited_by: caller }));
        }

        fn promote(ref self: ContractState, guild_id: u256, user: ContractAddress) {
            let caller = get_caller_address();
            self.assert_is_creator(guild_id, caller);

            let user_role = self.get_role(guild_id, user);
            assert(user_role == Role::Member, 'Promote only members');

            self.guild_members.write((guild_id, user), Role::Officer);

            self.emit(Event::UserPromoted(UserPromoted { guild_id, user, promoted_by: caller }));
        }

        fn demote(ref self: ContractState, guild_id: u256, user: ContractAddress) {
            let caller = get_caller_address();
            self.assert_is_creator(guild_id, caller);

            let user_role = self.get_role(guild_id, user);
            assert(user_role == Role::Officer, 'Demote only officers');

            self.guild_members.write((guild_id, user), Role::Member);

            self.emit(Event::UserDemoted(UserDemoted { guild_id, user, demoted_by: caller }));
        }

        fn kick(ref self: ContractState, guild_id: u256, user: ContractAddress) {
            let caller = get_caller_address();
            self.assert_is_creator_or_officer(guild_id, caller);

            let user_role = self.get_role(guild_id, user);
            assert(
                user_role == Role::Member || user_role == Role::Officer,
                'Kick only members/officers'
            );

            self.guild_members.write((guild_id, user), Role::None);

            self.emit(Event::UserKicked(UserKicked { guild_id, user, kicked_by: caller }));
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn get_role(self: @ContractState, guild_id: u256, user: ContractAddress) -> Role {
            self.guild_members.read((guild_id, user))
        }

        fn assert_is_creator(self: @ContractState, guild_id: u256, user: ContractAddress) {
            let role = self.get_role(guild_id, user);
            assert(role == Role::Creator, 'Not creator');
        }

        fn assert_is_creator_or_officer(
            self: @ContractState, guild_id: u256, user: ContractAddress
        ) {
            let role = self.get_role(guild_id, user);
            assert(role == Role::Creator || role == Role::Officer, 'Not authorized');
        }
    }
}
