use core::num::traits::Zero;
use core::panic_with_felt252;
use core::serde::Serde;
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{
    ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
    get_contract_address,
};

/// Guild Component v0.2
///
/// Core component for guild membership, roles, and permissions.
/// Uses bitmask-based permission system where each role has an `allowed_actions: u32`
/// field encoding which actions members of that role can perform.
///
/// The Governor contract is the sole admin — no owner key exists.
/// Role management (create/modify/delete) is governor-only.
/// Membership management (invite/kick/promote) is permission-based.
#[starknet::component]
pub mod GuildComponent {
    use guilds::interfaces::ponziland::{
        IPonziLandActionsDispatcher, IPonziLandActionsDispatcherTrait,
    };
    use guilds::interfaces::token::{IGuildTokenDispatcher, IGuildTokenDispatcherTrait};
    use guilds::models::constants::{
        ActionType, BPS_DENOMINATOR, DEFAULT_PLAYER_BPS, DEFAULT_SHAREHOLDER_BPS,
        DEFAULT_TREASURY_BPS, TOKEN_MULTIPLIER,
    };
    use guilds::models::events;
    use guilds::models::types::{
        DistributionPolicy, EpochSnapshot, Member, PendingInvite, PluginConfig, RedemptionWindow,
        Role, ShareOffer,
    };
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_interfaces::votes::{IVotesDispatcher, IVotesDispatcherTrait};
    use starknet::syscalls;
    use super::*;

    // ====================================================================
    // Storage
    // ====================================================================

    #[storage]
    pub struct Storage {
        // --- Identity ---
        pub guild_name: felt252,
        pub guild_ticker: felt252,
        // --- Cross-contract references ---
        pub token_address: ContractAddress,
        pub governor_address: ContractAddress,
        // --- Membership ---
        pub members: Map<ContractAddress, Member>,
        pub member_count: u32,
        pub founder_count: u32,
        pub pending_invites: Map<ContractAddress, PendingInvite>,
        // --- Roles ---
        pub roles: Map<u8, Role>,
        pub role_count: u8,
        // --- Plugins ---
        pub plugins: Map<felt252, PluginConfig>,
        pub plugin_count: u8,
        pub plugin_action_mask: u32,
        // --- Revenue ---
        pub distribution_policy: DistributionPolicy,
        pub current_epoch: u64,
        pub epoch_snapshots: Map<u64, EpochSnapshot>,
        pub revenue_token: ContractAddress,
        pub revenue_balance_checkpoint: u256,
        pub total_payout_weight: u32,
        pub role_member_count: Map<u8, u32>,
        pub member_last_claimed_epoch: Map<ContractAddress, u64>,
        pub shareholder_last_claimed_epoch: Map<ContractAddress, u64>,
        // --- Share Offerings ---
        pub active_offer: ShareOffer,
        pub has_active_offer: bool,
        pub redemption_window: RedemptionWindow,
        pub member_last_redemption_epoch: Map<ContractAddress, u64>,
        // --- Lifecycle ---
        pub is_dissolved: bool,
    }

    // ====================================================================
    // Events
    // ====================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RoleCreated: events::RoleCreated,
        RoleModified: events::RoleModified,
        RoleDeleted: events::RoleDeleted,
        MemberInvited: events::MemberInvited,
        MemberJoined: events::MemberJoined,
        MemberKicked: events::MemberKicked,
        MemberLeft: events::MemberLeft,
        MemberRoleChanged: events::MemberRoleChanged,
        InviteRevoked: events::InviteRevoked,
        CoreActionExecuted: events::CoreActionExecuted,
        PluginActionExecuted: events::PluginActionExecuted,
        PluginRegistered: events::PluginRegistered,
        PluginToggled: events::PluginToggled,
        EpochFinalized: events::EpochFinalized,
        PlayerRevenueClaimed: events::PlayerRevenueClaimed,
        ShareholderRevenueClaimed: events::ShareholderRevenueClaimed,
        DistributionPolicyChanged: events::DistributionPolicyChanged,
        ShareOfferCreated: events::ShareOfferCreated,
        SharesPurchased: events::SharesPurchased,
        SharesRedeemed: events::SharesRedeemed,
        GuildDissolved: events::GuildDissolved,
    }

    // ====================================================================
    // Errors
    // ====================================================================

    pub mod Errors {
        pub const NOT_A_MEMBER: felt252 = 'Not a guild member';
        pub const ALREADY_A_MEMBER: felt252 = 'Already a guild member';
        pub const ACTION_NOT_PERMITTED: felt252 = 'Action not permitted for role';
        pub const EXCEEDS_SPENDING_LIMIT: felt252 = 'Exceeds spending limit';
        pub const ONLY_GOVERNOR: felt252 = 'Only governor can do this';
        pub const ROLE_NOT_FOUND: felt252 = 'Role does not exist';
        pub const GUILD_NAME_INVALID: felt252 = 'Guild name cannot be zero';
        pub const GUILD_TICKER_INVALID: felt252 = 'Guild ticker cannot be zero';
        pub const TOKEN_ADDRESS_INVALID: felt252 = 'Token address cannot be zero';
        pub const GOVERNOR_ADDRESS_INVALID: felt252 = 'Governor address cannot be zero';
        pub const FOUNDER_ADDRESS_INVALID: felt252 = 'Founder address cannot be zero';
        pub const INVALID_ROLE_NAME: felt252 = 'Role name cannot be zero';
        pub const CANNOT_DELETE_FOUNDER: felt252 = 'Cannot delete founder role';
        pub const ROLE_HAS_MEMBERS: felt252 = 'Role still has assigned members';
        pub const GUILD_DISSOLVED: felt252 = 'Guild has been dissolved';
        pub const FOUNDER_MUST_NOT_KICK: felt252 = 'Founder role cannot be kickable';
        pub const INVITE_EXPIRED: felt252 = 'Invite has expired';
        pub const INVITE_EXPIRY_INVALID: felt252 = 'Invite expiry invalid';
        pub const NO_PENDING_INVITE: felt252 = 'No pending invite found';
        pub const CANNOT_KICK_SELF: felt252 = 'Cannot kick yourself';
        pub const CANNOT_KICK_HIGHER_RANK: felt252 = 'Cannot kick higher/equal rank';
        pub const CANNOT_MODIFY_HIGHER_RANK: felt252 = 'Cannot modify higher/equal rank';
        pub const TARGET_NOT_KICKABLE: felt252 = 'Target role is not kickable';
        pub const CANNOT_LEAVE_AS_LAST_FOUNDER: felt252 = 'Last founder cannot leave';
        pub const PROMOTE_DEPTH_EXCEEDED: felt252 = 'Promote depth exceeded';
        pub const CANNOT_PROMOTE_TO_HIGHER: felt252 = 'Cannot assign higher/equal role';
        pub const HAS_PENDING_INVITE: felt252 = 'Target has pending invite';
        pub const CANNOT_INVITE_TO_HIGHER: felt252 = 'Cannot invite to higher rank';
        pub const CALLER_CANNOT_INVITE: felt252 = 'Caller cannot invite';
        pub const CALLER_CANNOT_KICK: felt252 = 'Caller cannot kick';
        pub const CALLER_CANNOT_PROMOTE: felt252 = 'Caller cannot promote';
        pub const TARGET_ADDRESS_INVALID: felt252 = 'Target address cannot be zero';
        pub const PLUGIN_NOT_FOUND: felt252 = 'Plugin does not exist';
        pub const PLUGIN_DISABLED: felt252 = 'Plugin is disabled';
        pub const PLUGIN_ALREADY_EXISTS: felt252 = 'Plugin already exists';
        pub const PLUGIN_TARGET_INVALID: felt252 = 'Plugin target cannot be zero';
        pub const PLUGIN_ACTION_COUNT_ZERO: felt252 = 'Plugin action count must be > 0';
        pub const PLUGIN_ACTION_OUT_OF_RANGE: felt252 = 'Plugin action out of range';
        pub const PLUGIN_OFFSET_RESERVED: felt252 = 'Offset reserved for core';
        pub const PLUGIN_OFFSET_OVERFLOW: felt252 = 'Offset+count exceeds bitmask';
        pub const PLUGIN_OFFSET_COLLISION: felt252 = 'Plugin action bits overlap';
        pub const INVALID_CORE_ACTION: felt252 = 'Invalid core action type';
        pub const CORE_TARGET_INVALID: felt252 = 'Core action target cannot be zero';
        pub const CORE_TOKEN_INVALID: felt252 = 'Core action token cannot be zero';
        pub const PONZILAND_NOT_REGISTERED: felt252 = 'PonziLand plugin not registered';
        pub const INVALID_BPS_SUM: felt252 = 'Invalid policy bps sum';
        pub const REVENUE_TOKEN_INVALID: felt252 = 'Revenue token cannot be zero';
        pub const REVENUE_TOKEN_NOT_SET: felt252 = 'Revenue token not set';
        pub const REVENUE_BALANCE_BELOW_CHECKPOINT: felt252 = 'Revenue below checkpoint';
        pub const NO_NEW_REVENUE: felt252 = 'No new revenue to distribute';
        pub const EPOCH_NOT_FINALIZED: felt252 = 'Epoch not finalized';
        pub const ALREADY_CLAIMED_EPOCH: felt252 = 'Already claimed this epoch';
        pub const ACTIVE_OFFER_EXISTS: felt252 = 'Active offer already exists';
        pub const NO_ACTIVE_OFFER: felt252 = 'No active share offer';
        pub const OFFER_EXPIRED: felt252 = 'Share offer expired';
        pub const OFFER_EXCEEDS_MAX: felt252 = 'Purchase exceeds offer max';
        pub const OFFER_DEPOSIT_TOKEN_INVALID: felt252 = 'Offer deposit token invalid';
        pub const OFFER_MAX_TOTAL_INVALID: felt252 = 'Offer max_total must be > 0';
        pub const OFFER_PRICE_INVALID: felt252 = 'Offer price must be > 0';
        pub const OFFER_EXPIRY_INVALID: felt252 = 'Offer expiry invalid';
        pub const OFFER_AMOUNT_INVALID: felt252 = 'Purchase amount must be > 0';
        pub const OFFER_COST_ZERO: felt252 = 'Offer purchase cost rounds to zero';
        pub const REDEMPTION_NOT_ENABLED: felt252 = 'Redemption not enabled';
        pub const REDEMPTION_MAX_INVALID: felt252 = 'Redemption max invalid';
        pub const REDEMPTION_EPOCH_USAGE_INVALID: felt252 = 'Redemption epoch usage invalid';
        pub const REDEMPTION_AMOUNT_INVALID: felt252 = 'Redemption amount must be > 0';
        pub const REDEMPTION_LIMIT_EXCEEDED: felt252 = 'Exceeds epoch redemption limit';
        pub const REDEMPTION_COOLDOWN_ACTIVE: felt252 = 'Redemption cooldown active';
        pub const REDEMPTION_PAYOUT_ZERO: felt252 = 'Redemption payout rounds to zero';
    }

    // ====================================================================
    // Internal Implementation
    // ====================================================================

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>,
    > of InternalTrait<TContractState> {
        /// Initialize the guild component.
        /// Creates the founder role (role 0) and registers the founder as first member.
        fn initializer(
            ref self: ComponentState<TContractState>,
            guild_name: felt252,
            guild_ticker: felt252,
            token_address: ContractAddress,
            governor_address: ContractAddress,
            founder: ContractAddress,
            founder_role: Role,
        ) {
            assert!(guild_name != 0, "{}", Errors::GUILD_NAME_INVALID);
            assert!(guild_ticker != 0, "{}", Errors::GUILD_TICKER_INVALID);
            assert!(token_address != Zero::zero(), "{}", Errors::TOKEN_ADDRESS_INVALID);
            assert!(governor_address != Zero::zero(), "{}", Errors::GOVERNOR_ADDRESS_INVALID);
            assert!(founder != Zero::zero(), "{}", Errors::FOUNDER_ADDRESS_INVALID);
            assert!(founder_role.name != 0, "{}", Errors::INVALID_ROLE_NAME);
            assert!(!founder_role.can_be_kicked, "{}", Errors::FOUNDER_MUST_NOT_KICK);

            self.guild_name.write(guild_name);
            self.guild_ticker.write(guild_ticker);
            self.token_address.write(token_address);
            self.governor_address.write(governor_address);

            // Create founder role as role 0
            self.roles.write(0, founder_role);
            self.role_count.write(1);

            // Register founder as first member
            let member = Member { addr: founder, role_id: 0, joined_at: get_block_timestamp() };
            self.members.write(founder, member);
            self.member_count.write(1);
            self.founder_count.write(1);
            self.total_payout_weight.write(founder_role.payout_weight.into());
            self.role_member_count.write(0, 1);
            self
                .distribution_policy
                .write(
                    DistributionPolicy {
                        treasury_bps: DEFAULT_TREASURY_BPS,
                        player_bps: DEFAULT_PLAYER_BPS,
                        shareholder_bps: DEFAULT_SHAREHOLDER_BPS,
                    },
                );
        }

        // ----------------------------------------------------------------
        // Permission checks
        // ----------------------------------------------------------------

        /// Single permission gate: checks that caller is a member, their role
        /// has the requested action bit set, and the amount is within spending
        /// limit.
        ///
        /// The Governor always bypasses this check.
        fn check_permission(
            self: @ComponentState<TContractState>,
            caller: ContractAddress,
            action: u32,
            amount: u256,
        ) {
            self.assert_not_dissolved();

            // Governor bypasses all permission checks
            if caller == self.governor_address.read() {
                return;
            }

            let member = self.members.read(caller);
            assert!(member.addr != Zero::zero(), "{}", Errors::NOT_A_MEMBER);

            let role = self.roles.read(member.role_id);

            // Check action bitmask
            assert!(role.allowed_actions & action != 0, "{}", Errors::ACTION_NOT_PERMITTED);

            // Check spending limit (only for non-zero amounts)
            if amount > 0 {
                assert!(amount <= role.spending_limit, "{}", Errors::EXCEEDS_SPENDING_LIMIT);
            }
        }

        /// Assert that caller is the Governor contract.
        fn only_governor(self: @ComponentState<TContractState>) {
            assert!(
                get_caller_address() == self.governor_address.read(), "{}", Errors::ONLY_GOVERNOR,
            );
        }

        /// Assert guild is not dissolved.
        fn assert_not_dissolved(self: @ComponentState<TContractState>) {
            assert!(!self.is_dissolved.read(), "{}", Errors::GUILD_DISSOLVED);
        }

        /// Get a member, asserting they exist. Returns the Member struct.
        fn get_member_or_panic(
            self: @ComponentState<TContractState>, addr: ContractAddress,
        ) -> Member {
            let member = self.members.read(addr);
            assert!(member.addr != Zero::zero(), "{}", Errors::NOT_A_MEMBER);
            member
        }

        /// Assert that an address is NOT a member (for invite validation).
        fn assert_not_member(self: @ComponentState<TContractState>, addr: ContractAddress) {
            let member = self.members.read(addr);
            assert!(member.addr == Zero::zero(), "{}", Errors::ALREADY_A_MEMBER);
        }

        /// Get a role, asserting it exists (not deleted). Returns the Role.
        fn get_role_or_panic(self: @ComponentState<TContractState>, role_id: u8) -> Role {
            assert!(role_id < self.role_count.read(), "{}", Errors::ROLE_NOT_FOUND);
            let role = self.roles.read(role_id);
            // name == 0 means the role was deleted
            assert!(role.name != 0, "{}", Errors::ROLE_NOT_FOUND);
            role
        }

        fn plugin_or_panic(
            self: @ComponentState<TContractState>, plugin_id: felt252,
        ) -> PluginConfig {
            let config = self.plugins.read(plugin_id);
            assert!(config.target_contract != Zero::zero(), "{}", Errors::PLUGIN_NOT_FOUND);
            config
        }

        fn action_bit_from_position(self: @ComponentState<TContractState>, shift: u8) -> u32 {
            let mut value: u32 = 1;
            let mut i: u8 = 0;
            while i < shift {
                value = value * 2;
                i = i + 1;
            }
            value
        }

        /// Build a contiguous plugin action bitmask from [offset, offset + count).
        fn plugin_mask_from_range(
            self: @ComponentState<TContractState>, action_offset: u8, action_count: u8,
        ) -> u32 {
            let mut mask: u32 = 0;
            let mut i: u8 = 0;
            while i < action_count {
                mask = mask | self.action_bit_from_position(action_offset + i);
                i = i + 1;
            }
            mask
        }

        // ----------------------------------------------------------------
        // Role management (governor-only)
        // ----------------------------------------------------------------

        /// Create a new role. Returns the assigned role_id.
        fn create_role(ref self: ComponentState<TContractState>, role: Role) -> u8 {
            self.assert_not_dissolved();
            self.only_governor();
            assert!(role.name != 0, "{}", Errors::INVALID_ROLE_NAME);

            let role_id = self.role_count.read();
            self.roles.write(role_id, role);
            self.role_count.write(role_id + 1);

            self
                .emit(
                    events::RoleCreated {
                        role_id,
                        name: role.name,
                        allowed_actions: role.allowed_actions,
                        spending_limit: role.spending_limit,
                    },
                );

            role_id
        }

        /// Modify an existing role.
        /// Founder role (0) must always have can_be_kicked = false.
        fn modify_role(ref self: ComponentState<TContractState>, role_id: u8, role: Role) {
            self.assert_not_dissolved();
            self.only_governor();
            assert!(role.name != 0, "{}", Errors::INVALID_ROLE_NAME);
            let old_role = self.get_role_or_panic(role_id);

            // Founder role must never be kickable
            if role_id == 0 {
                assert!(!role.can_be_kicked, "{}", Errors::FOUNDER_MUST_NOT_KICK);
            }

            self.roles.write(role_id, role);

            let count = self.role_member_count.read(role_id);
            let old_weight: u32 = old_role.payout_weight.into();
            let new_weight: u32 = role.payout_weight.into();
            if old_weight != new_weight {
                self
                    .total_payout_weight
                    .write(
                        self.total_payout_weight.read() - old_weight * count + new_weight * count,
                    );
            }

            self
                .emit(
                    events::RoleModified {
                        role_id,
                        name: role.name,
                        allowed_actions: role.allowed_actions,
                        spending_limit: role.spending_limit,
                    },
                );
        }

        /// Delete a role by zeroing it out. Cannot delete role 0 (founder).
        fn delete_role(ref self: ComponentState<TContractState>, role_id: u8) {
            self.assert_not_dissolved();
            self.only_governor();
            assert!(role_id != 0, "{}", Errors::CANNOT_DELETE_FOUNDER);
            self.get_role_or_panic(role_id);
            assert!(self.role_member_count.read(role_id) == 0, "{}", Errors::ROLE_HAS_MEMBERS);

            // Zero out the role (name = 0 marks it as deleted)
            self
                .roles
                .write(
                    role_id,
                    Role {
                        name: 0,
                        can_invite: false,
                        can_kick: false,
                        can_promote_depth: 0,
                        can_be_kicked: false,
                        allowed_actions: 0,
                        spending_limit: 0,
                        payout_weight: 0,
                    },
                );

            self.emit(events::RoleDeleted { role_id });
        }

        // ----------------------------------------------------------------
        // Treasury + Plugins
        // ----------------------------------------------------------------

        fn execute_core_action(
            ref self: ComponentState<TContractState>,
            action_type: u32,
            target: ContractAddress,
            token: ContractAddress,
            amount: u256,
            calldata: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.check_permission(caller, action_type, amount);

            if action_type == ActionType::TRANSFER {
                assert!(target != Zero::zero(), "{}", Errors::CORE_TARGET_INVALID);
                assert!(token != Zero::zero(), "{}", Errors::CORE_TOKEN_INVALID);
                IERC20Dispatcher { contract_address: token }.transfer(target, amount);
                if token == self.revenue_token.read() {
                    let checkpoint = self.revenue_balance_checkpoint.read();
                    if checkpoint >= amount {
                        self.revenue_balance_checkpoint.write(checkpoint - amount);
                    } else {
                        self.revenue_balance_checkpoint.write(0);
                    }
                }
            } else if action_type == ActionType::APPROVE {
                assert!(target != Zero::zero(), "{}", Errors::CORE_TARGET_INVALID);
                assert!(token != Zero::zero(), "{}", Errors::CORE_TOKEN_INVALID);
                IERC20Dispatcher { contract_address: token }.approve(target, amount);
            } else if action_type == ActionType::EXECUTE {
                assert!(target != Zero::zero(), "{}", Errors::CORE_TARGET_INVALID);
                let mut execute_calldata = calldata;
                let selector: felt252 = Serde::deserialize(ref execute_calldata)
                    .expect('Missing selector');
                syscalls::call_contract_syscall(target, selector, execute_calldata)
                    .unwrap_syscall();
            } else {
                panic_with_felt252(Errors::INVALID_CORE_ACTION);
            }

            self
                .emit(
                    events::CoreActionExecuted {
                        action_type, target, token, amount, executed_by: caller,
                    },
                );
        }

        fn register_plugin(
            ref self: ComponentState<TContractState>,
            plugin_id: felt252,
            target_contract: ContractAddress,
            action_offset: u8,
            action_count: u8,
        ) {
            self.assert_not_dissolved();
            self.only_governor();

            let existing = self.plugins.read(plugin_id);
            assert!(existing.target_contract == Zero::zero(), "{}", Errors::PLUGIN_ALREADY_EXISTS);
            assert!(target_contract != Zero::zero(), "{}", Errors::PLUGIN_TARGET_INVALID);
            assert!(action_count > 0, "{}", Errors::PLUGIN_ACTION_COUNT_ZERO);

            let offset_u16: u16 = action_offset.into();
            let count_u16: u16 = action_count.into();
            assert!(offset_u16 >= 8, "{}", Errors::PLUGIN_OFFSET_RESERVED);
            assert!(offset_u16 + count_u16 <= 32, "{}", Errors::PLUGIN_OFFSET_OVERFLOW);
            let new_plugin_mask = self.plugin_mask_from_range(action_offset, action_count);
            let current_plugin_mask = self.plugin_action_mask.read();
            assert!(
                current_plugin_mask & new_plugin_mask == 0, "{}", Errors::PLUGIN_OFFSET_COLLISION,
            );

            self
                .plugins
                .write(
                    plugin_id,
                    PluginConfig { target_contract, enabled: true, action_offset, action_count },
                );
            self.plugin_count.write(self.plugin_count.read() + 1);
            self.plugin_action_mask.write(current_plugin_mask | new_plugin_mask);

            self
                .emit(
                    events::PluginRegistered {
                        plugin_id, target_contract, action_offset, action_count,
                    },
                );
        }

        fn toggle_plugin(
            ref self: ComponentState<TContractState>, plugin_id: felt252, enabled: bool,
        ) {
            self.assert_not_dissolved();
            self.only_governor();

            let mut config = self.plugin_or_panic(plugin_id);
            config.enabled = enabled;
            self.plugins.write(plugin_id, config);

            self.emit(events::PluginToggled { plugin_id, enabled });
        }

        fn execute_plugin_action(
            ref self: ComponentState<TContractState>,
            plugin_id: felt252,
            action_index: u8,
            selector: felt252,
            calldata: Span<felt252>,
        ) {
            let config = self.plugin_or_panic(plugin_id);
            assert!(config.enabled, "{}", Errors::PLUGIN_DISABLED);
            assert!(action_index < config.action_count, "{}", Errors::PLUGIN_ACTION_OUT_OF_RANGE);

            let shift = config.action_offset + action_index;
            let action_bit = self.action_bit_from_position(shift);
            let caller = get_caller_address();
            self.check_permission(caller, action_bit, 0);

            syscalls::call_contract_syscall(config.target_contract, selector, calldata)
                .unwrap_syscall();

            self
                .emit(
                    events::PluginActionExecuted { plugin_id, action_index, executed_by: caller },
                );
        }

        fn ponzi_buy_land(
            ref self: ComponentState<TContractState>,
            land_location: u16,
            token_for_sale: ContractAddress,
            sell_price: u256,
            amount_to_stake: u256,
        ) {
            let caller = get_caller_address();
            self.check_permission(caller, ActionType::PONZI_BUY_LAND, amount_to_stake);

            let config = self.plugins.read('ponziland');
            assert!(config.target_contract != Zero::zero(), "{}", Errors::PONZILAND_NOT_REGISTERED);
            assert!(config.enabled, "{}", Errors::PLUGIN_DISABLED);

            IPonziLandActionsDispatcher { contract_address: config.target_contract }
                .buy(land_location, token_for_sale, sell_price, amount_to_stake);
        }

        fn ponzi_set_price(
            ref self: ComponentState<TContractState>, land_location: u16, new_price: u256,
        ) {
            let caller = get_caller_address();
            self.check_permission(caller, ActionType::PONZI_SET_PRICE, 0);

            let config = self.plugins.read('ponziland');
            assert!(config.target_contract != Zero::zero(), "{}", Errors::PONZILAND_NOT_REGISTERED);
            assert!(config.enabled, "{}", Errors::PLUGIN_DISABLED);

            IPonziLandActionsDispatcher { contract_address: config.target_contract }
                .increase_price(land_location, new_price);
        }

        fn ponzi_claim_yield(ref self: ComponentState<TContractState>, land_location: u16) {
            let caller = get_caller_address();
            self.check_permission(caller, ActionType::PONZI_CLAIM_YIELD, 0);

            let config = self.plugins.read('ponziland');
            assert!(config.target_contract != Zero::zero(), "{}", Errors::PONZILAND_NOT_REGISTERED);
            assert!(config.enabled, "{}", Errors::PLUGIN_DISABLED);

            IPonziLandActionsDispatcher { contract_address: config.target_contract }
                .claim(land_location);
        }

        fn ponzi_increase_stake(
            ref self: ComponentState<TContractState>, land_location: u16, amount_to_stake: u256,
        ) {
            let caller = get_caller_address();
            self.check_permission(caller, ActionType::PONZI_STAKE, amount_to_stake);

            let config = self.plugins.read('ponziland');
            assert!(config.target_contract != Zero::zero(), "{}", Errors::PONZILAND_NOT_REGISTERED);
            assert!(config.enabled, "{}", Errors::PLUGIN_DISABLED);

            IPonziLandActionsDispatcher { contract_address: config.target_contract }
                .increase_stake(land_location, amount_to_stake);
        }

        fn ponzi_withdraw_stake(ref self: ComponentState<TContractState>, land_location: u16) {
            let caller = get_caller_address();
            self.check_permission(caller, ActionType::PONZI_UNSTAKE, 0);

            let config = self.plugins.read('ponziland');
            assert!(config.target_contract != Zero::zero(), "{}", Errors::PONZILAND_NOT_REGISTERED);
            assert!(config.enabled, "{}", Errors::PLUGIN_DISABLED);

            IPonziLandActionsDispatcher { contract_address: config.target_contract }
                .withdraw_stake(land_location);
        }

        fn set_distribution_policy(
            ref self: ComponentState<TContractState>, policy: DistributionPolicy,
        ) {
            self.assert_not_dissolved();
            self.only_governor();
            let total_bps = policy.treasury_bps + policy.player_bps + policy.shareholder_bps;
            assert!(total_bps == BPS_DENOMINATOR, "{}", Errors::INVALID_BPS_SUM);
            self.distribution_policy.write(policy);
            self
                .emit(
                    events::DistributionPolicyChanged {
                        treasury_bps: policy.treasury_bps,
                        player_bps: policy.player_bps,
                        shareholder_bps: policy.shareholder_bps,
                    },
                );
        }

        fn set_revenue_token(ref self: ComponentState<TContractState>, token: ContractAddress) {
            self.assert_not_dissolved();
            self.only_governor();
            assert!(token != Zero::zero(), "{}", Errors::REVENUE_TOKEN_INVALID);
            self.revenue_token.write(token);
            let balance = IERC20Dispatcher { contract_address: token }
                .balance_of(get_contract_address());
            self.revenue_balance_checkpoint.write(balance);
        }

        fn finalize_epoch(ref self: ComponentState<TContractState>) {
            let caller = get_caller_address();
            self.check_permission(caller, ActionType::DISTRIBUTE, 0);

            let revenue_token = self.revenue_token.read();
            assert!(revenue_token != Zero::zero(), "{}", Errors::REVENUE_TOKEN_NOT_SET);

            let current_balance = IERC20Dispatcher { contract_address: revenue_token }
                .balance_of(get_contract_address());
            let checkpoint = self.revenue_balance_checkpoint.read();
            assert!(
                current_balance >= checkpoint, "{}", Errors::REVENUE_BALANCE_BELOW_CHECKPOINT,
            );
            let new_revenue = current_balance - checkpoint;
            assert!(new_revenue > 0, "{}", Errors::NO_NEW_REVENUE);

            let policy = self.distribution_policy.read();
            let bps_denominator: u256 = BPS_DENOMINATOR.into();
            let treasury_amount = (new_revenue * policy.treasury_bps.into()) / bps_denominator;
            let player_amount = (new_revenue * policy.player_bps.into()) / bps_denominator;
            let shareholder_amount = new_revenue - treasury_amount - player_amount;

            let active_supply = IGuildTokenDispatcher {
                contract_address: self.token_address.read(),
            }
                .active_supply();

            let epoch = self.current_epoch.read();
            self
                .epoch_snapshots
                .write(
                    epoch,
                    EpochSnapshot {
                        total_revenue: new_revenue,
                        treasury_amount,
                        player_amount,
                        shareholder_amount,
                        active_supply,
                        total_payout_weight: self.total_payout_weight.read(),
                        finalized_at: get_block_timestamp(),
                    },
                );
            self.current_epoch.write(epoch + 1);
            self.revenue_balance_checkpoint.write(current_balance);
            let mut redemption_window = self.redemption_window.read();
            redemption_window.redeemed_this_epoch = 0;
            self.redemption_window.write(redemption_window);

            self
                .emit(
                    events::EpochFinalized {
                        epoch,
                        total_revenue: new_revenue,
                        treasury_amount,
                        player_amount,
                        shareholder_amount,
                    },
                );
        }

        fn claim_player_revenue(ref self: ComponentState<TContractState>, epoch: u64) {
            self.assert_not_dissolved();
            let caller = get_caller_address();
            let member = self.get_member_or_panic(caller);
            assert!(epoch < self.current_epoch.read(), "{}", Errors::EPOCH_NOT_FINALIZED);

            let next_claimable = self.member_last_claimed_epoch.read(caller);
            assert!(epoch == next_claimable, "{}", Errors::ALREADY_CLAIMED_EPOCH);

            let snapshot = self.epoch_snapshots.read(epoch);
            assert!(snapshot.total_payout_weight > 0, "No payout weight");

            let role = self.roles.read(member.role_id);
            let share = (snapshot.player_amount * role.payout_weight.into())
                / snapshot.total_payout_weight.into();

            // Effects before interactions (reentrancy-safe claim progression)
            self.member_last_claimed_epoch.write(caller, epoch + 1);

            let revenue_token = self.revenue_token.read();
            assert!(revenue_token != Zero::zero(), "{}", Errors::REVENUE_TOKEN_NOT_SET);
            IERC20Dispatcher { contract_address: revenue_token }.transfer(caller, share);
            let checkpoint = self.revenue_balance_checkpoint.read();
            if checkpoint >= share {
                self.revenue_balance_checkpoint.write(checkpoint - share);
            } else {
                self.revenue_balance_checkpoint.write(0);
            }

            self.emit(events::PlayerRevenueClaimed { member: caller, epoch, amount: share });
        }

        fn claim_shareholder_revenue(ref self: ComponentState<TContractState>, epoch: u64) {
            self.assert_not_dissolved();
            let caller = get_caller_address();
            assert!(epoch < self.current_epoch.read(), "{}", Errors::EPOCH_NOT_FINALIZED);

            let next_claimable = self.shareholder_last_claimed_epoch.read(caller);
            assert!(epoch == next_claimable, "{}", Errors::ALREADY_CLAIMED_EPOCH);

            let snapshot = self.epoch_snapshots.read(epoch);
            assert!(snapshot.active_supply > 0, "No active supply");

            let votes = IVotesDispatcher { contract_address: self.token_address.read() };
            let holder_balance = votes.get_past_votes(caller, snapshot.finalized_at);
            let share = (snapshot.shareholder_amount * holder_balance) / snapshot.active_supply;

            // Effects before interactions (reentrancy-safe claim progression)
            self.shareholder_last_claimed_epoch.write(caller, epoch + 1);

            let revenue_token = self.revenue_token.read();
            assert!(revenue_token != Zero::zero(), "{}", Errors::REVENUE_TOKEN_NOT_SET);
            IERC20Dispatcher { contract_address: revenue_token }.transfer(caller, share);
            let checkpoint = self.revenue_balance_checkpoint.read();
            if checkpoint >= share {
                self.revenue_balance_checkpoint.write(checkpoint - share);
            } else {
                self.revenue_balance_checkpoint.write(0);
            }

            self
                .emit(
                    events::ShareholderRevenueClaimed { shareholder: caller, epoch, amount: share },
                );
        }

        fn create_share_offer(ref self: ComponentState<TContractState>, offer: ShareOffer) {
            self.assert_not_dissolved();
            self.only_governor();
            if self.has_active_offer.read() {
                let active_offer = self.active_offer.read();
                if active_offer.expires_at > 0 {
                    if get_block_timestamp() >= active_offer.expires_at {
                        self.has_active_offer.write(false);
                    }
                }
            }
            assert!(!self.has_active_offer.read(), "{}", Errors::ACTIVE_OFFER_EXISTS);
            assert!(offer.deposit_token != Zero::zero(), "{}", Errors::OFFER_DEPOSIT_TOKEN_INVALID);
            assert!(offer.max_total > 0, "{}", Errors::OFFER_MAX_TOTAL_INVALID);
            assert!(offer.price_per_share > 0, "{}", Errors::OFFER_PRICE_INVALID);
            if offer.expires_at > 0 {
                assert!(
                    offer.expires_at > get_block_timestamp(),
                    "{}",
                    Errors::OFFER_EXPIRY_INVALID,
                );
            }

            self
                .active_offer
                .write(
                    ShareOffer {
                        deposit_token: offer.deposit_token,
                        max_total: offer.max_total,
                        minted_so_far: 0,
                        price_per_share: offer.price_per_share,
                        expires_at: offer.expires_at,
                    },
                );
            self.has_active_offer.write(true);

            self
                .emit(
                    events::ShareOfferCreated {
                        deposit_token: offer.deposit_token,
                        max_total: offer.max_total,
                        price_per_share: offer.price_per_share,
                        expires_at: offer.expires_at,
                    },
                );
        }

        fn buy_shares(ref self: ComponentState<TContractState>, amount: u256) {
            self.assert_not_dissolved();
            assert!(self.has_active_offer.read(), "{}", Errors::NO_ACTIVE_OFFER);
            assert!(amount > 0, "{}", Errors::OFFER_AMOUNT_INVALID);

            let caller = get_caller_address();
            let mut offer = self.active_offer.read();

            if offer.expires_at > 0 {
                assert!(get_block_timestamp() < offer.expires_at, "{}", Errors::OFFER_EXPIRED);
            }

            let next_minted = offer.minted_so_far + amount;
            assert!(next_minted <= offer.max_total, "{}", Errors::OFFER_EXCEEDS_MAX);

            let cost = (amount * offer.price_per_share) / TOKEN_MULTIPLIER;
            assert!(cost > 0, "{}", Errors::OFFER_COST_ZERO);

            // Effects before interactions (reentrancy-safe offer accounting)
            offer.minted_so_far = next_minted;
            self.active_offer.write(offer);

            if next_minted == offer.max_total {
                self.has_active_offer.write(false);
            }

            IERC20Dispatcher { contract_address: offer.deposit_token }
                .transfer_from(caller, get_contract_address(), cost);
            IGuildTokenDispatcher { contract_address: self.token_address.read() }
                .mint(caller, amount);

            self.emit(events::SharesPurchased { buyer: caller, amount, cost });
        }

        fn set_redemption_window(
            ref self: ComponentState<TContractState>, window: RedemptionWindow,
        ) {
            self.assert_not_dissolved();
            self.only_governor();
            if window.enabled {
                assert!(window.max_per_epoch > 0_u256, "{}", Errors::REDEMPTION_MAX_INVALID);
            }
            assert!(
                window.redeemed_this_epoch == 0,
                "{}",
                Errors::REDEMPTION_EPOCH_USAGE_INVALID,
            );
            self.redemption_window.write(window);
        }

        fn redeem_shares(ref self: ComponentState<TContractState>, amount: u256) {
            self.assert_not_dissolved();
            assert!(amount > 0, "{}", Errors::REDEMPTION_AMOUNT_INVALID);
            let caller = get_caller_address();
            let mut window = self.redemption_window.read();
            assert!(window.enabled, "{}", Errors::REDEMPTION_NOT_ENABLED);

            let next_redeemed = window.redeemed_this_epoch + amount;
            assert!(next_redeemed <= window.max_per_epoch, "{}", Errors::REDEMPTION_LIMIT_EXCEEDED);

            let current_epoch = self.current_epoch.read();
            let last_redemption_epoch = self.member_last_redemption_epoch.read(caller);
            assert!(
                current_epoch >= last_redemption_epoch + window.cooldown_epochs.into(),
                "{}",
                Errors::REDEMPTION_COOLDOWN_ACTIVE,
            );

            let revenue_token = self.revenue_token.read();
            assert!(revenue_token != Zero::zero(), "{}", Errors::REVENUE_TOKEN_NOT_SET);
            let treasury_balance = IERC20Dispatcher { contract_address: revenue_token }
                .balance_of(get_contract_address());
            let total_supply = IERC20Dispatcher { contract_address: self.token_address.read() }
                .total_supply();
            assert!(total_supply > 0, "No token supply");

            let payout = (treasury_balance * amount) / total_supply;
            assert!(payout > 0, "{}", Errors::REDEMPTION_PAYOUT_ZERO);

            // Effects before interactions (reentrancy-safe redemption accounting)
            window.redeemed_this_epoch = next_redeemed;
            self.redemption_window.write(window);
            self.member_last_redemption_epoch.write(caller, current_epoch);

            IGuildTokenDispatcher { contract_address: self.token_address.read() }
                .burn(caller, amount);
            IERC20Dispatcher { contract_address: revenue_token }.transfer(caller, payout);
            let checkpoint = self.revenue_balance_checkpoint.read();
            if checkpoint >= payout {
                self.revenue_balance_checkpoint.write(checkpoint - payout);
            } else {
                self.revenue_balance_checkpoint.write(0);
            }

            self.emit(events::SharesRedeemed { redeemer: caller, amount, payout });
        }

        fn dissolve(ref self: ComponentState<TContractState>) {
            self.assert_not_dissolved();
            self.only_governor();
            self.is_dissolved.write(true);
            self.emit(events::GuildDissolved { dissolved_at: get_block_timestamp() });
        }

        // ----------------------------------------------------------------
        // Lifecycle member management
        // ----------------------------------------------------------------

        fn invite_member(
            ref self: ComponentState<TContractState>,
            target: ContractAddress,
            role_id: u8,
            expires_at: u64,
        ) {
            self.assert_not_dissolved();
            assert!(target != Zero::zero(), "{}", Errors::TARGET_ADDRESS_INVALID);

            let caller = get_caller_address();
            let governor = self.governor_address.read();

            self.assert_not_member(target);
            let existing_invite = self.pending_invites.read(target);
            if existing_invite.invited_by != Zero::zero() {
                if existing_invite.expires_at > 0 {
                    if get_block_timestamp() >= existing_invite.expires_at {
                        self
                            .pending_invites
                            .write(
                                target,
                                PendingInvite {
                                    role_id: 0, invited_by: Zero::zero(), invited_at: 0, expires_at: 0,
                                },
                            );
                    }
                }
            }
            let refreshed_invite = self.pending_invites.read(target);
            assert!(refreshed_invite.invited_by == Zero::zero(), "{}", Errors::HAS_PENDING_INVITE);
            self.get_role_or_panic(role_id);
            if expires_at > 0 {
                assert!(expires_at > get_block_timestamp(), "{}", Errors::INVITE_EXPIRY_INVALID);
            }

            if caller != governor {
                let caller_member = self.get_member_or_panic(caller);
                let caller_role = self.get_role_or_panic(caller_member.role_id);
                assert!(caller_role.can_invite, "{}", Errors::CALLER_CANNOT_INVITE);
                assert!(caller_member.role_id < role_id, "{}", Errors::CANNOT_INVITE_TO_HIGHER);
            }

            let invite = PendingInvite {
                role_id, invited_by: caller, invited_at: get_block_timestamp(), expires_at,
            };
            self.pending_invites.write(target, invite);

            self.emit(events::MemberInvited { target, role_id, invited_by: caller, expires_at });
        }

        fn accept_invite(ref self: ComponentState<TContractState>) {
            self.assert_not_dissolved();

            let caller = get_caller_address();
            self.assert_not_member(caller);
            let invite = self.pending_invites.read(caller);
            assert!(invite.invited_by != Zero::zero(), "{}", Errors::NO_PENDING_INVITE);

            if invite.expires_at > 0 {
                assert!(get_block_timestamp() < invite.expires_at, "{}", Errors::INVITE_EXPIRED);
            }

            let role = self.get_role_or_panic(invite.role_id);

            let member = Member {
                addr: caller, role_id: invite.role_id, joined_at: get_block_timestamp(),
            };
            self.members.write(caller, member);
            self
                .pending_invites
                .write(
                    caller,
                    PendingInvite {
                        role_id: 0, invited_by: Zero::zero(), invited_at: 0, expires_at: 0,
                    },
                );
            self.member_count.write(self.member_count.read() + 1);
            if invite.role_id == 0 {
                self.founder_count.write(self.founder_count.read() + 1);
            }
            let weight: u32 = role.payout_weight.into();
            self.total_payout_weight.write(self.total_payout_weight.read() + weight);
            self
                .role_member_count
                .write(invite.role_id, self.role_member_count.read(invite.role_id) + 1);
            // New members can only claim player revenue from epochs finalized
            // after they join.
            self.member_last_claimed_epoch.write(caller, self.current_epoch.read());

            self.emit(events::MemberJoined { member: caller, role_id: invite.role_id });
        }

        fn kick_member(ref self: ComponentState<TContractState>, target: ContractAddress) {
            self.assert_not_dissolved();
            assert!(target != Zero::zero(), "{}", Errors::TARGET_ADDRESS_INVALID);

            let caller = get_caller_address();
            let governor = self.governor_address.read();

            if caller != governor {
                let caller_member = self.get_member_or_panic(caller);
                let caller_role = self.get_role_or_panic(caller_member.role_id);
                assert!(caller_role.can_kick, "{}", Errors::CALLER_CANNOT_KICK);
                assert!(caller != target, "{}", Errors::CANNOT_KICK_SELF);

                let target_member = self.get_member_or_panic(target);
                let target_role = self.get_role_or_panic(target_member.role_id);
                assert!(target_role.can_be_kicked, "{}", Errors::TARGET_NOT_KICKABLE);
                assert!(
                    caller_member.role_id < target_member.role_id,
                    "{}",
                    Errors::CANNOT_KICK_HIGHER_RANK,
                );
            }

            let target_member = self.get_member_or_panic(target);
            let role = self.roles.read(target_member.role_id);
            let weight: u32 = role.payout_weight.into();
            let current_weight = self.total_payout_weight.read();
            if current_weight >= weight {
                self.total_payout_weight.write(current_weight - weight);
            } else {
                self.total_payout_weight.write(0);
            }
            let role_count = self.role_member_count.read(target_member.role_id);
            if role_count > 0 {
                self.role_member_count.write(target_member.role_id, role_count - 1);
            }
            self.members.write(target, Member { addr: Zero::zero(), role_id: 0, joined_at: 0 });
            self.member_count.write(self.member_count.read() - 1);
            if target_member.role_id == 0 {
                self.founder_count.write(self.founder_count.read() - 1);
            }

            self.emit(events::MemberKicked { member: target, kicked_by: caller });
        }

        fn leave_guild(ref self: ComponentState<TContractState>) {
            self.assert_not_dissolved();

            let caller = get_caller_address();
            let member = self.get_member_or_panic(caller);

            if member.role_id == 0 {
                assert!(self.founder_count.read() > 1, "{}", Errors::CANNOT_LEAVE_AS_LAST_FOUNDER);
            }

            let role = self.roles.read(member.role_id);
            let weight: u32 = role.payout_weight.into();
            let current_weight = self.total_payout_weight.read();
            if current_weight >= weight {
                self.total_payout_weight.write(current_weight - weight);
            } else {
                self.total_payout_weight.write(0);
            }
            let role_count = self.role_member_count.read(member.role_id);
            if role_count > 0 {
                self.role_member_count.write(member.role_id, role_count - 1);
            }

            self.members.write(caller, Member { addr: Zero::zero(), role_id: 0, joined_at: 0 });
            self.member_count.write(self.member_count.read() - 1);
            if member.role_id == 0 {
                self.founder_count.write(self.founder_count.read() - 1);
            }

            self.emit(events::MemberLeft { member: caller });
        }

        fn change_member_role(
            ref self: ComponentState<TContractState>, target: ContractAddress, new_role_id: u8,
        ) {
            self.assert_not_dissolved();
            assert!(target != Zero::zero(), "{}", Errors::TARGET_ADDRESS_INVALID);

            let caller = get_caller_address();
            let governor = self.governor_address.read();
            let mut target_member = self.get_member_or_panic(target);

            if caller != governor {
                let caller_member = self.get_member_or_panic(caller);
                let caller_role = self.get_role_or_panic(caller_member.role_id);
                assert!(caller_role.can_promote_depth > 0, "{}", Errors::CALLER_CANNOT_PROMOTE);
                assert!(
                    caller_member.role_id < target_member.role_id,
                    "{}",
                    Errors::CANNOT_MODIFY_HIGHER_RANK,
                );
                assert!(
                    new_role_id > caller_member.role_id, "{}", Errors::CANNOT_PROMOTE_TO_HIGHER,
                );
                assert!(
                    new_role_id <= caller_member.role_id + caller_role.can_promote_depth,
                    "{}",
                    Errors::PROMOTE_DEPTH_EXCEEDED,
                );
            }

            self.get_role_or_panic(new_role_id);

            let old_role_id = target_member.role_id;
            if old_role_id == 0 && new_role_id != 0 {
                assert!(self.founder_count.read() > 1, "{}", Errors::CANNOT_LEAVE_AS_LAST_FOUNDER);
            }
            target_member.role_id = new_role_id;
            self.members.write(target, target_member);

            let old_role = self.roles.read(old_role_id);
            let new_role = self.roles.read(new_role_id);
            let old_weight: u32 = old_role.payout_weight.into();
            let new_weight: u32 = new_role.payout_weight.into();
            let current_weight = self.total_payout_weight.read();
            if current_weight >= old_weight {
                self.total_payout_weight.write(current_weight - old_weight + new_weight);
            } else {
                self.total_payout_weight.write(new_weight);
            }

            let old_count = self.role_member_count.read(old_role_id);
            if old_count > 0 {
                self.role_member_count.write(old_role_id, old_count - 1);
            }
            self.role_member_count.write(new_role_id, self.role_member_count.read(new_role_id) + 1);

            if old_role_id == 0 && new_role_id != 0 {
                self.founder_count.write(self.founder_count.read() - 1);
            } else if old_role_id != 0 && new_role_id == 0 {
                self.founder_count.write(self.founder_count.read() + 1);
            }

            self
                .emit(
                    events::MemberRoleChanged {
                        member: target, old_role_id, new_role_id, changed_by: caller,
                    },
                );
        }

        fn revoke_invite(ref self: ComponentState<TContractState>, target: ContractAddress) {
            self.assert_not_dissolved();
            assert!(target != Zero::zero(), "{}", Errors::TARGET_ADDRESS_INVALID);

            let caller = get_caller_address();
            let invite = self.pending_invites.read(target);
            assert!(invite.invited_by != Zero::zero(), "{}", Errors::NO_PENDING_INVITE);

            if caller != self.governor_address.read() {
                assert!(caller == invite.invited_by, "{}", Errors::ACTION_NOT_PERMITTED);
            }

            self
                .pending_invites
                .write(
                    target,
                    PendingInvite {
                        role_id: 0, invited_by: Zero::zero(), invited_at: 0, expires_at: 0,
                    },
                );

            self.emit(events::InviteRevoked { target, revoked_by: caller });
        }
    }
}
