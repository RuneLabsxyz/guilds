use guilds::guild::guild_contract::GuildComponent::Rank;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IGuild<TState> {
    /// Invite a new member with a starting rank.
    fn invite_member(ref self: TState, member: ContractAddress);

    /// Kick a member from the guild.
    fn kick_member(ref self: TState, member: ContractAddress);

    /// Create a new rank with specified permissions and name.
    fn create_rank(
        ref self: TState,
        rank_name: felt252,
        can_invite: bool,
        can_kick: bool,
        promote: u8,
        can_be_kicked: bool,
    );

    fn get_rank_permissions(ref self: TState) -> Array<Rank>;

    /// Delete a rank by its ID.
    fn delete_rank(ref self: TState, rank_id: u8);

    /// Change the permissions of a rank by its ID.
    fn change_rank_permissions(
        ref self: TState,
        rank_id: u8,
        can_invite: bool,
        can_kick: bool,
        promote: u8,
        can_be_kicked: bool,
    );
}

#[starknet::interface]
pub trait IGuildMetadata<TState> {
    /// Returns the guild name.
    fn get_guild_name(self: @TState) -> felt252;

    /// Returns the owner of the guild.
    fn get_owner(self: @TState) -> ContractAddress;

    /// Check the number of ranks in the guild.
    fn max_rank(self: @TState) -> u8;
}

