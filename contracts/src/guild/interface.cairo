use starknet::ContractAddress;

#[starknet::interface]
pub trait IGuild<TState> {
    /// Returns the rank of a member. Returns 0 if not a member.
    fn get_member_rank(self: @TState, member: ContractAddress) -> u8;

    /// Invite a new member with a starting rank.
    fn invite_member(ref self: TState, member: ContractAddress, rank: u8);

    /// Kick a member from the guild.
    fn kick_member(ref self: TState, member: ContractAddress);

    /// Promote a member to a higher rank.
    fn promote_member(ref self: TState, member: ContractAddress, new_rank: u8);

    /// Update the maximum number of ranks. Only top-rank members can update.
    fn update_max_rank(ref self: TState, new_max_rank: u8);
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

