#[starknet::contract]
pub mod Guild {
    use core::panic_with_felt252;
    use guilds::guild::guild_contract::GuildComponent;
    use guilds::guild::guild_contract::GuildComponent::InternalImpl;
    use guilds::interfaces::guild::{IGuild, IGuildView};
    use guilds::models::types::{
        DistributionPolicy, EpochSnapshot, Member, PendingInvite, PluginConfig, RedemptionWindow,
        Role, ShareOffer,
    };
    use starknet::ContractAddress;
    use starknet::storage::{StorageMapReadAccess, StoragePointerReadAccess};

    component!(path: GuildComponent, storage: guild, event: GuildEvent);

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        pub guild: GuildComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        GuildEvent: GuildComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        guild_name: felt252,
        guild_ticker: felt252,
        token_address: ContractAddress,
        governor_address: ContractAddress,
        founder: ContractAddress,
        founder_role: Role,
    ) {
        self
            .guild
            .initializer(
                guild_name, guild_ticker, token_address, governor_address, founder, founder_role,
            );
    }

    #[abi(embed_v0)]
    impl GuildImpl of IGuild<ContractState> {
        fn invite_member(
            ref self: ContractState, target: ContractAddress, role_id: u8, expires_at: u64,
        ) {
            self.guild.invite_member(target, role_id, expires_at);
        }

        fn accept_invite(ref self: ContractState) {
            self.guild.accept_invite();
        }

        fn kick_member(ref self: ContractState, target: ContractAddress) {
            self.guild.kick_member(target);
        }

        fn leave_guild(ref self: ContractState) {
            self.guild.leave_guild();
        }

        fn change_member_role(ref self: ContractState, target: ContractAddress, new_role_id: u8) {
            self.guild.change_member_role(target, new_role_id);
        }

        fn revoke_invite(ref self: ContractState, target: ContractAddress) {
            self.guild.revoke_invite(target);
        }

        fn create_role(ref self: ContractState, role: Role) {
            self.guild.create_role(role);
        }

        fn modify_role(ref self: ContractState, role_id: u8, role: Role) {
            self.guild.modify_role(role_id, role);
        }

        fn delete_role(ref self: ContractState, role_id: u8) {
            self.guild.delete_role(role_id);
        }

        fn execute_core_action(
            ref self: ContractState,
            action_type: u32,
            target: ContractAddress,
            token: ContractAddress,
            amount: u256,
            calldata: Span<felt252>,
        ) {
            self.guild.execute_core_action(action_type, target, token, amount, calldata);
        }

        fn execute_plugin_action(
            ref self: ContractState,
            plugin_id: felt252,
            action_index: u8,
            selector: felt252,
            calldata: Span<felt252>,
        ) {
            self.guild.execute_plugin_action(plugin_id, action_index, selector, calldata);
        }

        fn ponzi_buy_land(
            ref self: ContractState,
            land_location: u16,
            token_for_sale: ContractAddress,
            sell_price: u256,
            amount_to_stake: u256,
        ) {
            self.guild.ponzi_buy_land(land_location, token_for_sale, sell_price, amount_to_stake);
        }

        fn ponzi_set_price(ref self: ContractState, land_location: u16, new_price: u256) {
            self.guild.ponzi_set_price(land_location, new_price);
        }

        fn ponzi_claim_yield(ref self: ContractState, land_location: u16) {
            self.guild.ponzi_claim_yield(land_location);
        }

        fn ponzi_increase_stake(
            ref self: ContractState, land_location: u16, amount_to_stake: u256,
        ) {
            self.guild.ponzi_increase_stake(land_location, amount_to_stake);
        }

        fn ponzi_withdraw_stake(ref self: ContractState, land_location: u16) {
            self.guild.ponzi_withdraw_stake(land_location);
        }

        fn register_plugin(
            ref self: ContractState,
            plugin_id: felt252,
            target_contract: ContractAddress,
            action_offset: u8,
            action_count: u8,
        ) {
            self.guild.register_plugin(plugin_id, target_contract, action_offset, action_count);
        }

        fn toggle_plugin(ref self: ContractState, plugin_id: felt252, enabled: bool) {
            self.guild.toggle_plugin(plugin_id, enabled);
        }

        fn set_distribution_policy(ref self: ContractState, policy: DistributionPolicy) {
            let _ = policy;
            panic_with_felt252('Not implemented');
        }

        fn finalize_epoch(ref self: ContractState) {
            panic_with_felt252('Not implemented');
        }

        fn claim_player_revenue(ref self: ContractState, epoch: u64) {
            let _ = epoch;
            panic_with_felt252('Not implemented');
        }

        fn claim_shareholder_revenue(ref self: ContractState, epoch: u64) {
            let _ = epoch;
            panic_with_felt252('Not implemented');
        }

        fn create_share_offer(ref self: ContractState, offer: ShareOffer) {
            let _ = offer;
            panic_with_felt252('Not implemented');
        }

        fn buy_shares(ref self: ContractState, amount: u256) {
            let _ = amount;
            panic_with_felt252('Not implemented');
        }

        fn set_redemption_window(ref self: ContractState, window: RedemptionWindow) {
            let _ = window;
            panic_with_felt252('Not implemented');
        }

        fn redeem_shares(ref self: ContractState, amount: u256) {
            let _ = amount;
            panic_with_felt252('Not implemented');
        }

        fn dissolve(ref self: ContractState) {
            self.guild.dissolve();
        }
    }

    #[abi(embed_v0)]
    impl GuildViewImpl of IGuildView<ContractState> {
        fn get_guild_name(self: @ContractState) -> felt252 {
            self.guild.guild_name.read()
        }

        fn get_guild_ticker(self: @ContractState) -> felt252 {
            self.guild.guild_ticker.read()
        }

        fn get_token_address(self: @ContractState) -> ContractAddress {
            self.guild.token_address.read()
        }

        fn get_governor_address(self: @ContractState) -> ContractAddress {
            self.guild.governor_address.read()
        }

        fn get_member(self: @ContractState, addr: ContractAddress) -> Member {
            self.guild.members.read(addr)
        }

        fn get_role(self: @ContractState, role_id: u8) -> Role {
            self.guild.roles.read(role_id)
        }

        fn get_role_count(self: @ContractState) -> u8 {
            self.guild.role_count.read()
        }

        fn get_member_count(self: @ContractState) -> u32 {
            self.guild.member_count.read()
        }

        fn get_pending_invite(self: @ContractState, addr: ContractAddress) -> PendingInvite {
            self.guild.pending_invites.read(addr)
        }

        fn get_plugin(self: @ContractState, plugin_id: felt252) -> PluginConfig {
            self.guild.plugins.read(plugin_id)
        }

        fn get_distribution_policy(self: @ContractState) -> DistributionPolicy {
            self.guild.distribution_policy.read()
        }

        fn get_current_epoch(self: @ContractState) -> u64 {
            self.guild.current_epoch.read()
        }

        fn get_epoch_snapshot(self: @ContractState, epoch: u64) -> EpochSnapshot {
            self.guild.epoch_snapshots.read(epoch)
        }

        fn get_active_offer(self: @ContractState) -> ShareOffer {
            self.guild.active_offer.read()
        }

        fn has_active_offer(self: @ContractState) -> bool {
            self.guild.has_active_offer.read()
        }

        fn get_redemption_window(self: @ContractState) -> RedemptionWindow {
            self.guild.redemption_window.read()
        }
    }
}
