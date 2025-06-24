use starknet::ContractAddress;

#[starknet::interface]
pub trait IGuild<TState> {
    /// Invite a new member with a starting rank.
    fn invite_member(ref self: TState, member: ContractAddress);

    /// Kick a member from the guild.
    fn kick_member(ref self: TState, member: ContractAddress);
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

