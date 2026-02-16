use core::num::traits::Zero;
use starknet::storage::{
    Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
    StoragePointerWriteAccess,
};
use starknet::{ContractAddress, get_block_timestamp, get_caller_address};

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
    use guilds::models::events;
    use guilds::models::types::{
        DistributionPolicy, EpochSnapshot, Member, PendingInvite, PluginConfig, RedemptionWindow,
        Role, ShareOffer,
    };
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

        // --- Revenue ---
        pub distribution_policy: DistributionPolicy,
        pub current_epoch: u64,
        pub epoch_snapshots: Map<u64, EpochSnapshot>,
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
        pub const CANNOT_DELETE_FOUNDER: felt252 = 'Cannot delete founder role';
        pub const GUILD_DISSOLVED: felt252 = 'Guild has been dissolved';
        pub const FOUNDER_MUST_NOT_KICK: felt252 = 'Founder role cannot be kickable';
        pub const INVITE_EXPIRED: felt252 = 'Invite has expired';
        pub const NO_PENDING_INVITE: felt252 = 'No pending invite found';
        pub const CANNOT_KICK_SELF: felt252 = 'Cannot kick yourself';
        pub const CANNOT_KICK_HIGHER_RANK: felt252 = 'Cannot kick higher/equal rank';
        pub const TARGET_NOT_KICKABLE: felt252 = 'Target role is not kickable';
        pub const CANNOT_LEAVE_AS_LAST_FOUNDER: felt252 = 'Last founder cannot leave';
        pub const PROMOTE_DEPTH_EXCEEDED: felt252 = 'Promote depth exceeded';
        pub const CANNOT_PROMOTE_TO_HIGHER: felt252 = 'Cannot assign higher/equal role';
        pub const HAS_PENDING_INVITE: felt252 = 'Target has pending invite';
        pub const CANNOT_INVITE_TO_HIGHER: felt252 = 'Cannot invite to higher rank';
        pub const CALLER_CANNOT_INVITE: felt252 = 'Caller cannot invite';
        pub const CALLER_CANNOT_KICK: felt252 = 'Caller cannot kick';
        pub const CALLER_CANNOT_PROMOTE: felt252 = 'Caller cannot promote';
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
                get_caller_address() == self.governor_address.read(),
                "{}",
                Errors::ONLY_GOVERNOR,
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

        // ----------------------------------------------------------------
        // Role management (governor-only)
        // ----------------------------------------------------------------

        /// Create a new role. Returns the assigned role_id.
        fn create_role(ref self: ComponentState<TContractState>, role: Role) -> u8 {
            self.only_governor();

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
            self.only_governor();
            self.get_role_or_panic(role_id);

            // Founder role must never be kickable
            if role_id == 0 {
                assert!(!role.can_be_kicked, "{}", Errors::FOUNDER_MUST_NOT_KICK);
            }

            self.roles.write(role_id, role);

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
            self.only_governor();
            assert!(role_id != 0, "{}", Errors::CANNOT_DELETE_FOUNDER);
            self.get_role_or_panic(role_id);

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
        // Lifecycle member management
        // ----------------------------------------------------------------

        fn invite_member(
            ref self: ComponentState<TContractState>,
            target: ContractAddress,
            role_id: u8,
            expires_at: u64,
        ) {
            self.assert_not_dissolved();

            let caller = get_caller_address();
            let governor = self.governor_address.read();

            if caller != governor {
                let caller_member = self.get_member_or_panic(caller);
                let caller_role = self.get_role_or_panic(caller_member.role_id);
                assert!(caller_role.can_invite, "{}", Errors::CALLER_CANNOT_INVITE);

                self.assert_not_member(target);

                let existing_invite = self.pending_invites.read(target);
                assert!(
                    existing_invite.invited_by == Zero::zero(),
                    "{}",
                    Errors::HAS_PENDING_INVITE,
                );

                assert!(caller_member.role_id < role_id, "{}", Errors::CANNOT_INVITE_TO_HIGHER);
                self.get_role_or_panic(role_id);
            }

            let invite = PendingInvite {
                role_id,
                invited_by: caller,
                invited_at: get_block_timestamp(),
                expires_at,
            };
            self.pending_invites.write(target, invite);

            self.emit(events::MemberInvited { target, role_id, invited_by: caller, expires_at });
        }

        fn accept_invite(ref self: ComponentState<TContractState>) {
            self.assert_not_dissolved();

            let caller = get_caller_address();
            let invite = self.pending_invites.read(caller);
            assert!(invite.invited_by != Zero::zero(), "{}", Errors::NO_PENDING_INVITE);

            if invite.expires_at > 0 {
                assert!(get_block_timestamp() < invite.expires_at, "{}", Errors::INVITE_EXPIRED);
            }

            self.get_role_or_panic(invite.role_id);

            let member = Member { addr: caller, role_id: invite.role_id, joined_at: get_block_timestamp() };
            self.members.write(caller, member);
            self
                .pending_invites
                .write(
                    caller,
                    PendingInvite {
                        role_id: 0,
                        invited_by: Zero::zero(),
                        invited_at: 0,
                        expires_at: 0,
                    },
                );
            self.member_count.write(self.member_count.read() + 1);
            if invite.role_id == 0 {
                self.founder_count.write(self.founder_count.read() + 1);
            }

            self.emit(events::MemberJoined { member: caller, role_id: invite.role_id });
        }

        fn kick_member(ref self: ComponentState<TContractState>, target: ContractAddress) {
            self.assert_not_dissolved();

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
                assert!(caller_member.role_id < target_member.role_id, "{}", Errors::CANNOT_KICK_HIGHER_RANK);
            }

            let target_member = self.get_member_or_panic(target);
            self
                .members
                .write(target, Member { addr: Zero::zero(), role_id: 0, joined_at: 0 });
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
                assert!(
                    self.founder_count.read() > 1,
                    "{}",
                    Errors::CANNOT_LEAVE_AS_LAST_FOUNDER,
                );
            }

            self
                .members
                .write(caller, Member { addr: Zero::zero(), role_id: 0, joined_at: 0 });
            self.member_count.write(self.member_count.read() - 1);
            if member.role_id == 0 {
                self.founder_count.write(self.founder_count.read() - 1);
            }

            self.emit(events::MemberLeft { member: caller });
        }

        fn change_member_role(
            ref self: ComponentState<TContractState>,
            target: ContractAddress,
            new_role_id: u8,
        ) {
            self.assert_not_dissolved();

            let caller = get_caller_address();
            let governor = self.governor_address.read();

            if caller != governor {
                let caller_member = self.get_member_or_panic(caller);
                let caller_role = self.get_role_or_panic(caller_member.role_id);
                assert!(caller_role.can_promote_depth > 0, "{}", Errors::CALLER_CANNOT_PROMOTE);
                assert!(new_role_id > caller_member.role_id, "{}", Errors::CANNOT_PROMOTE_TO_HIGHER);
                assert!(
                    new_role_id <= caller_member.role_id + caller_role.can_promote_depth,
                    "{}",
                    Errors::PROMOTE_DEPTH_EXCEEDED,
                );
            }

            self.get_role_or_panic(new_role_id);

            let mut target_member = self.get_member_or_panic(target);
            let old_role_id = target_member.role_id;
            target_member.role_id = new_role_id;
            self.members.write(target, target_member);

            if old_role_id == 0 && new_role_id != 0 {
                self.founder_count.write(self.founder_count.read() - 1);
            } else if old_role_id != 0 && new_role_id == 0 {
                self.founder_count.write(self.founder_count.read() + 1);
            }

            self
                .emit(
                    events::MemberRoleChanged {
                        member: target,
                        old_role_id,
                        new_role_id,
                        changed_by: caller,
                    },
                );
        }

        fn revoke_invite(ref self: ComponentState<TContractState>, target: ContractAddress) {
            self.assert_not_dissolved();

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
                        role_id: 0,
                        invited_by: Zero::zero(),
                        invited_at: 0,
                        expires_at: 0,
                    },
                );

            self.emit(events::InviteRevoked { target, revoked_by: caller });
        }
    }
}
