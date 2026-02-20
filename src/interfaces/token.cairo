use guilds::models::types::InactivityFlag;
use starknet::ContractAddress;

/// GuildToken custom operations (beyond standard ERC20 + ERC20Votes).
/// The standard ERC20 and Votes interfaces are exposed via OZ component embeds.
#[starknet::interface]
pub trait IGuildToken<TState> {
    // --- Activity ---

    /// Update caller's last activity timestamp (proves liveness).
    fn ping(ref self: TState);

    /// Get the last activity timestamp for an account.
    fn get_last_activity(self: @TState, account: ContractAddress) -> u64;

    /// Get the inactivity threshold in seconds.
    fn get_inactivity_threshold(self: @TState) -> u64;

    // --- Inactivity ---

    /// Flag an account as inactive (anyone can call if threshold exceeded).
    fn flag_inactive(ref self: TState, account: ContractAddress);

    /// Clear caller's own inactivity flag (proves liveness).
    fn clear_inactivity_flag(ref self: TState);

    /// Check if an account is flagged as inactive.
    fn is_flagged_inactive(self: @TState, account: ContractAddress) -> bool;

    /// Get the inactivity flag details for an account.
    fn get_inactivity_flag(self: @TState, account: ContractAddress) -> InactivityFlag;

    // --- Supply ---

    /// Get the active supply (total supply minus flagged-inactive balances).
    fn active_supply(self: @TState) -> u256;

    // --- Minting/Burning (Governor only) ---

    /// Mint new tokens to a recipient. Only callable by the Governor.
    fn mint(ref self: TState, recipient: ContractAddress, amount: u256);

    /// Burn tokens from an account. Only callable by the Governor.
    fn burn(ref self: TState, account: ContractAddress, amount: u256);

    /// Get the guild contract address this token is associated with.
    fn get_guild_address(self: @TState) -> ContractAddress;

    // --- Factory Init ---

    /// One-shot setter for guild_address (only callable when current value is zero).
    fn set_guild_address(ref self: TState, guild_address: ContractAddress);

    /// One-shot setter for governor_address (only callable when current value is zero).
    fn set_governor_address(ref self: TState, governor_address: ContractAddress);
}
