# Guild System Specification v0.2

> **Status**: Draft — reconstructed from design sessions  
> **Target**: Starknet (Cairo 2.13.1, OpenZeppelin 3.0.0)  
> **Scope**: On-chain guild contracts, SDK, and UI integration for PonziLand and other Starknet games

---

## Table of Contents

1. [Overview](#1-overview)
2. [Design Principles](#2-design-principles)
3. [Contract Architecture](#3-contract-architecture)
4. [Data Model](#4-data-model)
5. [Role & Permission System](#5-role--permission-system)
6. [Guild Lifecycle](#6-guild-lifecycle)
7. [Guild Token (ERC20Votes)](#7-guild-token-erc20votes)
8. [Governor](#8-governor)
9. [Treasury & Plugin System](#9-treasury--plugin-system)
10. [Revenue Distribution](#10-revenue-distribution)
11. [Share Offerings & Redemption](#11-share-offerings--redemption)
12. [Inactivity System](#12-inactivity-system)
13. [Factory & Registry](#13-factory--registry)
14. [PonziLand Integration](#14-ponziland-integration)
15. [Security Considerations](#15-security-considerations)
16. [SDK & UI Integration](#16-sdk--ui-integration)

---

## 1. Overview

Guilds function as **DAOs**, **investment funds**, and **esports teams** for on-chain games. Each guild is a set of three co-deployed contracts:

| Contract | Purpose |
|----------|---------|
| **Guild** | Membership, roles, permissions, treasury, plugin execution |
| **GuildToken** | ERC20 with voting power (ERC20Votes) — single token for governance, dividends, and redemption |
| **Governor** | Proposal creation, voting, execution with timelock |

**Key insight**: Governance is the default authority, but governance can **delegate** specific actions to custom roles. Members with the right role can then act without a vote — "governance only when needed."

### Single Token Model

One ERC20 per guild. This token simultaneously represents:
- **Voting power** (via ERC20Votes delegation)
- **Dividend rights** (epoch-based revenue claims)
- **Redemption rights** (burn tokens to withdraw proportional treasury share)
- **Membership weight** (token balance as economic stake)

No dual-token / multi-class share structure. Simple and transparent.

---

## 2. Design Principles

1. **No owner key** — The Governor contract is the sole admin. No EOA can unilaterally control the guild. The guild creator has no special on-chain privilege after deployment (they do get the initial token supply, giving them initial voting power).

2. **Governance only when needed** — Instead of voting on every action, governance votes to create roles with specific permissions. Role-holders can then act autonomously within their granted scope.

3. **Bitmask permissions** — A single `u32` (`allowed_actions`) encodes what actions a role can perform. Each bit corresponds to an action type. This is compact, gas-efficient, and extensible.

4. **Guild contract IS the treasury** — No separate vault contract. The guild contract holds all funds directly. Simpler architecture, fewer cross-contract calls.

5. **Plugin system** — Games register as plugins with action offsets in the bitmask. PonziLand actions start at bit 8. Other games can register at higher offsets.

6. **Epoch-based claims** — Revenue is not pushed to members. Instead, epoch snapshots record earnings and members pull (claim) their share. Prevents gas-bombing and scales to any member count.

7. **Composability** — The system is designed as Starknet components, allowing other projects to embed guild functionality or extend it.

---

## 3. Contract Architecture

### 3.1 Contract Relationships

```
┌─────────────────────────────────────────────────────┐
│                   GuildFactory                       │
│  - deploys Guild + GuildToken + Governor as a set    │
│  - maintains registry of all guilds                  │
│  - enforces name/ticker uniqueness                   │
└───────────────┬─────────────────────────────────────┘
                │ deploys
                ▼
┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│       Guild          │   │     GuildToken        │   │      Governor        │
│                      │   │                       │   │                      │
│ - Membership mgmt    │◄──│ - ERC20 + Votes       │──►│ - Proposals          │
│ - Roles & perms      │   │ - Activity tracking   │   │ - Voting             │
│ - Treasury (holds $) │   │ - Inactivity flagging │   │ - Timelock execution │
│ - Plugin execution   │   │ - Mint/burn (gov only)│   │ - Calls into Guild   │
│ - Revenue distrib.   │   └──────────────────────┘   └──────────────────────┘
│ - Share offers       │
└──────────────────────┘
```

### 3.2 Component Composition

Each contract is built from OpenZeppelin components plus custom components:

**Guild Contract:**
- `GuildComponent` (custom) — membership, roles, permissions
- `TreasuryComponent` (custom) — plugin execution, spending limits
- `RevenueComponent` (custom) — distribution policy, epoch snapshots, claims
- `ShareComponent` (custom) — share offerings, redemption windows

**GuildToken Contract:**
- `ERC20Component` (OZ) — standard ERC20
- `ERC20VotesComponent` (OZ) — voting power delegation, checkpoints
- `NoncesComponent` (OZ) — nonce management for votes
- `ActivityComponent` (custom) — last-activity tracking, inactivity flagging

**Governor Contract:**
- `GovernorComponent` (OZ) — core proposal/vote/execute
- `GovernorSettingsComponent` (OZ) — voting delay, voting period, proposal threshold
- `GovernorCountingSimpleComponent` (OZ) — for/against/abstain counting
- `GovernorVotesComponent` (OZ) — reads voting power from GuildToken
- `GovernorTimelockExecutionComponent` (OZ) — timelock between vote pass and execution
- `TimelockControllerComponent` (OZ) — manages the timelock queue

### 3.3 Cross-Contract Calls

| Caller | Target | Function | When |
|--------|--------|----------|------|
| Governor | Guild | `execute_governance_action()` | After proposal passes + timelock |
| Guild | GuildToken | `mint()`, `burn()` | Via governance action |
| Guild | External (e.g. PonziLand) | Game-specific calls | Via `execute_plugin_action()` |
| GuildToken | GuildToken | `delegate()` | Token holder delegates voting power |
| Anyone | Governor | `propose()`, `cast_vote()` | If they hold enough tokens |

---

## 4. Data Model

### 4.1 Core Structs

```cairo
/// A role defines a set of permissions and economic weight within the guild.
/// Roles are created/modified exclusively through governance proposals.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct Role {
    /// Human-readable name (short, stored as felt252)
    name: felt252,
    /// Whether members with this role can invite new members
    can_invite: bool,
    /// Whether members with this role can kick other members
    can_kick: bool,
    /// How many rank levels below this role the member can promote to.
    /// 0 = cannot promote anyone. 1 = can promote to one level below self. etc.
    can_promote_depth: u8,
    /// Whether members with this role can be kicked by others
    can_be_kicked: bool,
    /// Bitmask of allowed action types (see ActionType constants).
    /// Each bit corresponds to one action. Bit 0 = TRANSFER, Bit 1 = APPROVE, etc.
    /// Plugin actions start at higher bit offsets (e.g. PonziLand at bit 8).
    allowed_actions: u32,
    /// Maximum amount (in base token, e.g. LORDS) this role can spend per transaction.
    /// 0 = no spending allowed. u256::MAX = unlimited.
    spending_limit: u256,
    /// Weight for revenue distribution. Higher = larger share of player pool.
    /// Relative to sum of all role payout_weights across active members.
    payout_weight: u16,
}

/// A guild member.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct Member {
    /// The member's wallet address
    addr: ContractAddress,
    /// The role_id assigned to this member (index into roles map)
    role_id: u8,
    /// Block timestamp when the member joined
    joined_at: u64,
}

/// A pending invitation that has not yet been accepted.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct PendingInvite {
    /// The role the invited address will receive upon accepting
    role_id: u8,
    /// Who sent the invite
    invited_by: ContractAddress,
    /// Block timestamp when the invite was created
    invited_at: u64,
    /// Block timestamp after which the invite expires (0 = never expires)
    expires_at: u64,
}

/// Configuration for a plugin (external game integration).
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct PluginConfig {
    /// The target contract address for this plugin (e.g. PonziLand game contract)
    target_contract: ContractAddress,
    /// Whether this plugin is currently enabled
    enabled: bool,
    /// Starting bit offset in the allowed_actions bitmask for this plugin's actions.
    /// Core actions use bits 0-7. PonziLand uses 8-15. Other games at 16+.
    action_offset: u8,
    /// Number of distinct actions this plugin defines (max bits it uses)
    action_count: u8,
}

/// Revenue distribution policy — how incoming revenue is split.
/// All values in basis points (1 bps = 0.01%). Must sum to 10000.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct DistributionPolicy {
    /// Percentage kept in treasury (retained earnings)
    treasury_bps: u16,
    /// Percentage distributed to active players/members (split by payout_weight)
    player_bps: u16,
    /// Percentage distributed to token holders (proportional to token balance)
    shareholder_bps: u16,
}

/// A share offering — allows the guild to sell new tokens for capital.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct ShareOffer {
    /// The ERC20 token accepted as payment (e.g. LORDS, ETH)
    deposit_token: ContractAddress,
    /// Maximum total tokens to mint in this offering
    max_total: u256,
    /// How many tokens have been minted so far in this offering
    minted_so_far: u256,
    /// Price per guild token, denominated in deposit_token
    price_per_share: u256,
    /// Block timestamp after which the offering closes (0 = no expiry)
    expires_at: u64,
}

/// Redemption window configuration — allows token holders to burn tokens
/// and withdraw proportional treasury share.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct RedemptionWindow {
    /// Whether redemption is currently enabled
    enabled: bool,
    /// Maximum tokens that can be redeemed per epoch
    max_per_epoch: u256,
    /// How many tokens have been redeemed in the current epoch
    redeemed_this_epoch: u256,
    /// Number of epochs a member must wait after redeeming before redeeming again
    cooldown_epochs: u32,
}

/// Tracks when a token holder was flagged for inactivity.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct InactivityFlag {
    /// Block timestamp when the holder was flagged
    flagged_at: u64,
    /// Who flagged them
    flagged_by: ContractAddress,
}

/// Snapshot of revenue for one epoch.
#[derive(Drop, Serde, Copy, starknet::Store, PartialEq)]
struct EpochSnapshot {
    /// Total revenue received during this epoch
    total_revenue: u256,
    /// Amount allocated to treasury
    treasury_amount: u256,
    /// Amount allocated to player pool
    player_amount: u256,
    /// Amount allocated to shareholder pool
    shareholder_amount: u256,
    /// Total active token supply at snapshot time (for shareholder calculations)
    active_supply: u256,
    /// Block timestamp when this epoch was finalized
    finalized_at: u64,
}
```

### 4.2 Action Type Constants

Core actions occupy bits 0–7. Plugin actions start at bit 8.

```cairo
/// Core treasury/guild action types (bits 0-7)
mod ActionType {
    /// Transfer ERC20 tokens from treasury
    const TRANSFER: u32 = 0x1;         // bit 0
    /// Approve ERC20 spending from treasury
    const APPROVE: u32 = 0x2;          // bit 1
    /// Execute arbitrary call from guild contract
    const EXECUTE: u32 = 0x4;          // bit 2
    /// Modify guild settings (non-role, non-governance settings)
    const SETTINGS: u32 = 0x8;         // bit 3
    /// Manage share offerings
    const SHARE_MGMT: u32 = 0x10;      // bit 4
    /// Trigger epoch finalization and distribution
    const DISTRIBUTE: u32 = 0x20;      // bit 5
    // bits 6-7 reserved for future core actions

    /// PonziLand plugin actions (bits 8-15)
    const PONZI_BUY_LAND: u32 = 0x100;       // bit 8
    const PONZI_SELL_LAND: u32 = 0x200;       // bit 9
    const PONZI_SET_PRICE: u32 = 0x400;       // bit 10
    const PONZI_CLAIM_YIELD: u32 = 0x800;     // bit 11
    const PONZI_STAKE: u32 = 0x1000;          // bit 12
    const PONZI_UNSTAKE: u32 = 0x2000;        // bit 13
    // bits 14-15 reserved for future PonziLand actions

    // bits 16-23: available for plugin slot 2
    // bits 24-31: available for plugin slot 3
}
```

### 4.3 Storage Layout

**Guild Contract Storage:**
```cairo
#[storage]
struct Storage {
    // --- Identity ---
    guild_name: felt252,
    guild_ticker: felt252,
    description: ByteArray,

    // --- Cross-contract references ---
    token_address: ContractAddress,
    governor_address: ContractAddress,

    // --- Membership ---
    members: Map<ContractAddress, Member>,
    member_count: u32,
    pending_invites: Map<ContractAddress, PendingInvite>,

    // --- Roles ---
    roles: Map<u8, Role>,
    role_count: u8,

    // --- Plugins ---
    plugins: Map<felt252, PluginConfig>,  // plugin_id => config
    plugin_count: u8,

    // --- Revenue ---
    distribution_policy: DistributionPolicy,
    current_epoch: u64,
    epoch_snapshots: Map<u64, EpochSnapshot>,
    member_last_claimed_epoch: Map<ContractAddress, u64>,
    shareholder_last_claimed_epoch: Map<ContractAddress, u64>,

    // --- Share Offerings ---
    active_offer: ShareOffer,
    has_active_offer: bool,
    redemption_window: RedemptionWindow,
    member_last_redemption_epoch: Map<ContractAddress, u64>,
}
```

**GuildToken Contract Storage:**
```cairo
#[storage]
struct Storage {
    // OZ ERC20 + Votes storage via substorage
    #[substorage(v0)]
    erc20: ERC20Component::Storage,
    #[substorage(v0)]
    votes: ERC20VotesComponent::Storage,
    #[substorage(v0)]
    nonces: NoncesComponent::Storage,

    // --- Activity Tracking ---
    guild_address: ContractAddress,
    last_activity: Map<ContractAddress, u64>,    // address => last active timestamp
    inactivity_flags: Map<ContractAddress, InactivityFlag>,
    inactivity_threshold: u64,                   // seconds of inactivity before flaggable
}
```

---

## 5. Role & Permission System

### 5.1 Overview

Roles replace the v0.1 rank system with a more powerful bitmask-based permission model.

- **Role 0** is always the "founder" role, created at guild initialization. It cannot be deleted.
- New roles are created exclusively through **governance proposals**.
- Roles can be modified or deleted through governance proposals.
- Members are assigned to roles. A member's permissions come entirely from their role.

### 5.2 Permission Check (`_check_permission`)

Every privileged action goes through a single gate:

```cairo
fn _check_permission(self: @ComponentState, caller: ContractAddress, action: u32, amount: u256) {
    let member = self.members.read(caller);
    assert!(member.addr != Zero::zero(), "Not a guild member");

    let role = self.roles.read(member.role_id);

    // Check action bitmask
    assert!(role.allowed_actions & action != 0, "Action not permitted for role");

    // Check spending limit (only for actions involving fund transfers)
    if amount > 0 {
        assert!(amount <= role.spending_limit, "Exceeds spending limit");
    }
}
```

### 5.3 Governor Override

The Governor contract can execute any action on the Guild, bypassing role checks. This is enforced by checking `get_caller_address() == self.governor_address.read()` before the role check.

```cairo
fn _only_governor(self: @ComponentState) {
    assert!(
        get_caller_address() == self.governor_address.read(),
        "Only governor can perform this action"
    );
}
```

### 5.4 Permission Hierarchy for Member Management

| Action | Who can do it |
|--------|---------------|
| **Invite** | Any member whose role has `can_invite = true` |
| **Kick** | Any member whose role has `can_kick = true`, target's role has `can_be_kicked = true`, AND kicker's role_id < target's role_id (numerically lower = more senior) |
| **Promote** | Any member can promote another member up to `can_promote_depth` levels below their own role. Cannot promote to equal or higher rank. |
| **Create/modify/delete role** | Governor only |
| **Change member's role** | Governor, or member with promote permission (within depth) |

---

## 6. Guild Lifecycle

### 6.1 Creation

Guilds are created through the `GuildFactory`:

1. Creator calls `factory.create_guild(name, ticker, description, initial_deposit_token, initial_deposit_amount, roles_config)`
2. Factory deploys `GuildToken` → gets token address
3. Factory deploys `Guild` → configured with token address
4. Factory deploys `Governor` → configured with token address + guild address
5. Guild's `governor_address` is set to the Governor
6. GuildToken mints initial supply (e.g. 1000 tokens) to the creator
7. Creator's deposit is transferred to the Guild contract (treasury)
8. Factory registers the guild in its registry

**Constraints:**
- Guild name: 4–50 characters, must be unique across all active guilds
- Ticker: 1–5 characters, must be globally unique
- Initial deposit: minimum threshold (configurable in factory, e.g. $10 equivalent)
- Creator automatically becomes a member with role 0

### 6.2 Inviting Members

```
invite_member(target: ContractAddress, role_id: u8, expires_at: u64)
```

1. Caller must be a member with `can_invite = true` on their role
2. Caller's role_id must be < target role_id (can only invite to lower roles)
3. Target must not already be a member or have a pending invite
4. Creates a `PendingInvite` with expiry timestamp
5. Emits `MemberInvited` event

### 6.3 Accepting an Invite

```
accept_invite()
```

1. Caller must have a pending invite
2. If `expires_at > 0`, current block timestamp must be < expires_at
3. Creates `Member` entry with the role from the invite
4. Clears the pending invite
5. Increments `member_count`
6. Emits `MemberJoined` event

### 6.4 Kicking a Member

```
kick_member(target: ContractAddress)
```

1. Caller must be a member with `can_kick = true`
2. Target must be a member with `can_be_kicked = true`
3. Caller's role_id must be < target's role_id
4. Caller cannot kick themselves
5. Removes `Member` entry
6. Decrements `member_count`
7. Emits `MemberKicked` event
8. **Note**: Kicked members keep their tokens (governance tokens are separate from membership)

### 6.5 Leaving a Guild

```
leave_guild()
```

1. Any member can leave voluntarily
2. Cannot leave if you are the last member with role 0 (prevents orphaned guild)
3. Removes `Member` entry
4. Decrements `member_count`
5. Emits `MemberLeft` event
6. Member keeps their tokens

### 6.6 Promoting / Demoting a Member

```
change_member_role(target: ContractAddress, new_role_id: u8)
```

1. Caller's role must have `can_promote_depth > 0`
2. `new_role_id` must be > caller's role_id (can only assign to lower roles)
3. `new_role_id` must be within `can_promote_depth` levels of caller
4. Target must be a member
5. Emits `MemberRoleChanged` event

### 6.7 Dissolving a Guild

Dissolution is a governance action:

1. Proposal passes to dissolve the guild
2. All pending revenue claims are finalized
3. Treasury is distributed proportionally to token holders
4. Guild is marked as dissolved in the factory registry
5. No further actions can be performed

---

## 7. Guild Token (ERC20Votes)

### 7.1 Token Properties

| Property | Value |
|----------|-------|
| Standard | ERC20 + ERC20Votes (OZ 3.0.0) |
| Decimals | 18 |
| Initial supply | Configurable (default: 1000 * 10^18) |
| Minting | Governor only |
| Burning | Governor only (or via redemption mechanism) |
| Transfer | Standard ERC20 (unrestricted) |
| Delegation | ERC20Votes standard — holders must delegate to activate voting power |

### 7.2 Activity Tracking

The GuildToken contract tracks the last activity timestamp for each holder:

```cairo
fn _update_activity(ref self: ComponentState, account: ContractAddress) {
    self.last_activity.write(account, get_block_timestamp());
}
```

Activity is updated on:
- Token transfer (sender and receiver)
- Delegation
- Voting
- Explicit `ping()` call

### 7.3 Active Supply

For governance and revenue calculations, "active supply" excludes tokens held by flagged-inactive addresses:

```cairo
fn active_supply(self: @ComponentState) -> u256 {
    self.total_supply() - self.inactive_balance()
}
```

### 7.4 Ping

```
ping()
```

Allows a holder to update their last activity timestamp without performing any other action. Prevents false inactivity flags.

---

## 8. Governor

### 8.1 OZ Governor Integration

The Governor uses OpenZeppelin's modular governor system:

- **GovernorComponent** — core proposal lifecycle
- **GovernorSettingsComponent** — configurable parameters
- **GovernorCountingSimpleComponent** — For/Against/Abstain vote counting
- **GovernorVotesComponent** — reads voting power from GuildToken's ERC20Votes
- **GovernorTimelockExecutionComponent** — enforces delay between vote pass and execution

### 8.2 Governor Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Voting delay | 1 day (86400 blocks at 1s/block) | Time between proposal creation and voting start |
| Voting period | 3 days (259200 blocks) | Duration of the voting period |
| Proposal threshold | 1% of total supply | Minimum tokens to create a proposal |
| Quorum | 10% of active supply | Minimum participation for a valid vote |
| Timelock delay | 1 day (86400 seconds) | Delay between vote pass and execution |

All parameters are modifiable through governance proposals.

### 8.3 Proposal Types

Proposals encode calls to the Guild contract. Common proposal types:

| Proposal | Target | Function |
|----------|--------|----------|
| Create role | Guild | `create_role(...)` |
| Modify role | Guild | `modify_role(role_id, ...)` |
| Delete role | Guild | `delete_role(role_id)` |
| Mint tokens | GuildToken | `mint(recipient, amount)` |
| Burn tokens | GuildToken | `burn(account, amount)` |
| Change distribution | Guild | `set_distribution_policy(...)` |
| Register plugin | Guild | `register_plugin(...)` |
| Create share offering | Guild | `create_share_offer(...)` |
| Configure redemption | Guild | `set_redemption_window(...)` |
| Dissolve guild | Guild | `dissolve()` |
| Execute arbitrary call | Guild | `execute_core_action(...)` |

### 8.4 Execution Flow

```
propose() → [voting delay] → vote() → [voting period] → queue() → [timelock] → execute()
```

1. **Propose**: Token holder with >= threshold creates proposal with calldata
2. **Vote**: During voting period, token holders cast For/Against/Abstain
3. **Queue**: If quorum met and For > Against, proposal is queued in timelock
4. **Execute**: After timelock delay, anyone can trigger execution

---

## 9. Treasury & Plugin System

### 9.1 Guild as Treasury

The Guild contract address IS the treasury. It holds:
- ERC20 tokens (LORDS, ETH, STRK, etc.)
- Any tokens received from game revenue

### 9.2 Core Treasury Actions

```cairo
/// Execute a core treasury action (transfer, approve, etc.)
/// Requires caller to have the corresponding action bit in their role.
fn execute_core_action(
    ref self: ContractState,
    action_type: u32,
    target: ContractAddress,
    token: ContractAddress,
    amount: u256,
    calldata: Span<felt252>,
)
```

Permission check: `_check_permission(caller, action_type, amount)`

### 9.3 Plugin System

Plugins allow the guild to interact with external game contracts through typed, permissioned actions.

#### Registering a Plugin (Governor only)

```cairo
fn register_plugin(
    ref self: ContractState,
    plugin_id: felt252,
    target_contract: ContractAddress,
    action_offset: u8,
    action_count: u8,
)
```

- `plugin_id`: unique identifier (e.g. `'ponziland'`)
- `action_offset`: starting bit in the bitmask (must not overlap with existing plugins)
- `action_count`: number of actions this plugin uses

#### Executing a Plugin Action

```cairo
fn execute_plugin_action(
    ref self: ContractState,
    plugin_id: felt252,
    action_index: u8,
    calldata: Span<felt252>,
)
```

1. Look up `PluginConfig` by `plugin_id`
2. Assert plugin is enabled
3. Compute action bit: `1 << (config.action_offset + action_index)`
4. `_check_permission(caller, action_bit, 0)` (spending limit checked separately if funds involved)
5. Call `config.target_contract` with the calldata

### 9.4 PonziLand Convenience Functions

Typed wrappers around `execute_plugin_action` for common PonziLand operations:

```cairo
fn ponzi_buy_land(ref self: ContractState, land_id: u256, price: u256) { ... }
fn ponzi_sell_land(ref self: ContractState, land_id: u256, min_price: u256) { ... }
fn ponzi_set_price(ref self: ContractState, land_id: u256, new_price: u256) { ... }
fn ponzi_claim_yield(ref self: ContractState) { ... }
fn ponzi_stake(ref self: ContractState, amount: u256) { ... }
fn ponzi_unstake(ref self: ContractState, amount: u256) { ... }
```

Each of these checks the corresponding `PONZI_*` action bit on the caller's role.

---

## 10. Revenue Distribution

### 10.1 Distribution Policy

Revenue is split according to `DistributionPolicy`:

```
treasury_bps + player_bps + shareholder_bps = 10000 (100%)
```

Default: `{ treasury_bps: 3000, player_bps: 5000, shareholder_bps: 2000 }`

### 10.2 Epoch Model

Revenue accumulates in the guild contract. Periodically (triggered by a member with `DISTRIBUTE` permission or by governance), an epoch is finalized:

```cairo
fn finalize_epoch(ref self: ContractState)
```

1. Calculates total revenue received since last epoch
2. Applies `DistributionPolicy` to split revenue into three pools
3. Records `EpochSnapshot` with amounts and active supply
4. Increments `current_epoch`
5. Treasury portion stays in the contract
6. Player and shareholder portions become claimable

### 10.3 Claiming Revenue

**Player claims** (based on role payout_weight):

```cairo
fn claim_player_revenue(ref self: ContractState, epoch: u64)
```

- Caller must be a member
- Member's share = `(role.payout_weight / total_weight_of_active_members) * player_amount`
- Marks epoch as claimed for this member

**Shareholder claims** (based on token balance at snapshot):

```cairo
fn claim_shareholder_revenue(ref self: ContractState, epoch: u64)
```

- Caller must hold tokens (need not be a member)
- Share = `(caller_balance_at_snapshot / active_supply_at_snapshot) * shareholder_amount`
- Uses ERC20Votes checkpoints for historical balance lookup
- Marks epoch as claimed for this shareholder

---

## 11. Share Offerings & Redemption

### 11.1 Share Offerings

Governance can create an offering to raise capital:

```cairo
fn create_share_offer(
    ref self: ContractState,
    deposit_token: ContractAddress,
    max_total: u256,
    price_per_share: u256,
    expires_at: u64,
)
```

Buyers participate:

```cairo
fn buy_shares(ref self: ContractState, amount: u256)
```

1. Transfers `amount * price_per_share` of `deposit_token` from buyer to guild
2. Mints `amount` guild tokens to buyer
3. Updates `minted_so_far`
4. Fails if offering expired or max_total reached

### 11.2 Redemption

Token holders can burn tokens to withdraw proportional treasury value:

```cairo
fn redeem_shares(ref self: ContractState, amount: u256)
```

1. Checks `redemption_window.enabled`
2. Checks `redeemed_this_epoch + amount <= max_per_epoch`
3. Checks cooldown (member hasn't redeemed within `cooldown_epochs`)
4. Calculates proportional value: `amount / total_supply * treasury_value`
5. Burns `amount` tokens from caller
6. Transfers proportional treasury assets to caller
7. Updates `redeemed_this_epoch`

---

## 12. Inactivity System

### 12.1 Purpose

Prevents lost wallets from permanently locking governance power. If a token holder doesn't interact for a configurable period, their tokens can be flagged as inactive and eventually burned (through governance vote).

### 12.2 Activity Tracking

The GuildToken tracks `last_activity` for each holder. Updated on:
- Transfer (send or receive)
- Delegation
- Voting
- Explicit `ping()` call

### 12.3 Flagging

```cairo
fn flag_inactive(ref self: ContractState, account: ContractAddress)
```

1. Anyone can call this
2. Checks `block_timestamp - last_activity[account] > inactivity_threshold`
3. Creates `InactivityFlag { flagged_at, flagged_by }`
4. Emits `InactivityFlagged` event

### 12.4 Clearing a Flag

```cairo
fn clear_inactivity_flag(ref self: ContractState)
```

1. Called by the flagged account (proves they're active)
2. Removes the `InactivityFlag`
3. Updates `last_activity`
4. Emits `InactivityCleared` event

### 12.5 Burning Inactive Tokens

After a flag has been active for a governance-defined grace period, a governance proposal can burn the flagged account's tokens:

1. Proposal: "Burn tokens of inactive account X"
2. If passed, GuildToken burns the account's entire balance
3. This reduces total supply, increasing remaining holders' proportional share

---

## 13. Factory & Registry

### 13.1 GuildFactory

```cairo
#[starknet::interface]
trait IGuildFactory<TState> {
    /// Deploy a new guild (Guild + GuildToken + Governor)
    fn create_guild(
        ref self: TState,
        name: felt252,
        ticker: felt252,
        description: ByteArray,
        deposit_token: ContractAddress,
        deposit_amount: u256,
        initial_token_supply: u256,
        governor_config: GovernorConfig,
    ) -> (ContractAddress, ContractAddress, ContractAddress);

    /// Get guild info by address
    fn get_guild(self: @TState, guild_address: ContractAddress) -> GuildRegistryEntry;

    /// Check if a name is taken
    fn is_name_taken(self: @TState, name: felt252) -> bool;

    /// Check if a ticker is taken
    fn is_ticker_taken(self: @TState, ticker: felt252) -> bool;

    /// Get all guild addresses
    fn get_all_guilds(self: @TState) -> Array<ContractAddress>;

    /// Get guild count
    fn guild_count(self: @TState) -> u32;
}
```

### 13.2 Registry

```cairo
#[derive(Drop, Serde, Copy, starknet::Store)]
struct GuildRegistryEntry {
    guild_address: ContractAddress,
    token_address: ContractAddress,
    governor_address: ContractAddress,
    name: felt252,
    ticker: felt252,
    creator: ContractAddress,
    created_at: u64,
    is_active: bool,
}
```

### 13.3 GovernorConfig

```cairo
#[derive(Drop, Serde, Copy)]
struct GovernorConfig {
    voting_delay: u64,
    voting_period: u64,
    proposal_threshold: u256,
    quorum_bps: u16,       // basis points of active supply
    timelock_delay: u64,
}
```

---

## 14. PonziLand Integration

### 14.1 How Guilds Play PonziLand

- The Guild contract address is a player in PonziLand
- When the guild buys land, `get_caller_address()` returns the Guild contract address → the guild owns the land
- Revenue from land goes to the Guild contract address
- Members with PonziLand action permissions can manage guild lands

### 14.2 Integration Points

| PonziLand Action | Guild Function | Permission Bit |
|-----------------|----------------|----------------|
| Buy land | `ponzi_buy_land()` | `PONZI_BUY_LAND` |
| Sell land | `ponzi_sell_land()` | `PONZI_SELL_LAND` |
| Set price | `ponzi_set_price()` | `PONZI_SET_PRICE` |
| Claim yield | `ponzi_claim_yield()` | `PONZI_CLAIM_YIELD` |
| Stake | `ponzi_stake()` | `PONZI_STAKE` |
| Unstake | `ponzi_unstake()` | `PONZI_UNSTAKE` |

### 14.3 Cross-Contract Call Pattern

```cairo
fn ponzi_buy_land(ref self: ContractState, land_id: u256, price: u256) {
    let caller = get_caller_address();
    self._check_permission(caller, ActionType::PONZI_BUY_LAND, price);

    let plugin = self.plugins.read('ponziland');
    assert!(plugin.enabled, "PonziLand plugin not enabled");

    // Build calldata for PonziLand's buy function
    let mut calldata = array![];
    land_id.serialize(ref calldata);

    // Approve PonziLand to spend from guild treasury
    // Then call PonziLand's buy function
    IPonziLandDispatcher { contract_address: plugin.target_contract }
        .buy_land(land_id);
}
```

---

## 15. Security Considerations

### 15.1 Access Control

- **No owner key**: All admin actions go through governance
- **Bitmask permissions**: Compact, auditable, no ambiguous role hierarchies
- **Spending limits**: Per-role caps prevent a compromised role from draining treasury
- **Timelock**: Gives token holders time to react to malicious proposals

### 15.2 Economic Security

- **Quorum requirements**: Prevents small minorities from passing proposals
- **Redemption limits**: `max_per_epoch` prevents bank runs
- **Cooldown periods**: Prevents rapid cycles of redeem-buy-redeem
- **Inactivity threshold**: Protects against lost wallet governance deadlock

### 15.3 Anti-Abuse

- **Invite expiry**: Prevents stale invites from being accepted months later
- **Kick hierarchy**: Cannot kick equal or higher rank members
- **Self-kick prevention**: Members cannot kick themselves (use `leave_guild` instead)
- **Minimum deposit**: Prevents spam guild creation

### 15.4 Reentrancy

- Follow checks-effects-interactions pattern
- Use OZ ReentrancyGuard for functions that make external calls
- Particularly important for: `redeem_shares`, `execute_plugin_action`, `buy_shares`

---

## 16. SDK & UI Integration

### 16.1 TypeScript SDK (`@runelabsxyz/guilds-sdk`)

The SDK provides:
- Contract ABIs and type-safe wrappers
- Multicall batching for read operations
- Event indexing helpers
- Proposal creation helpers (encode calldata for common proposal types)

### 16.2 Svelte UI Components

Target integration into PonziLand's existing Svelte frontend:
- Guild dashboard (members, treasury, active proposals)
- Role management interface
- Proposal creation and voting UI
- Revenue claim interface
- Share offering participation

### 16.3 API Surface

```typescript
interface GuildSDK {
  // Read
  getGuild(address: string): Promise<GuildInfo>;
  getMembers(guildAddress: string): Promise<Member[]>;
  getRoles(guildAddress: string): Promise<Role[]>;
  getProposals(governorAddress: string): Promise<Proposal[]>;
  getTreasuryBalance(guildAddress: string, token: string): Promise<bigint>;

  // Write
  createGuild(params: CreateGuildParams): Promise<TransactionResult>;
  invite(target: string, roleId: number): Promise<TransactionResult>;
  acceptInvite(): Promise<TransactionResult>;
  propose(params: ProposeParams): Promise<TransactionResult>;
  vote(proposalId: bigint, support: VoteType): Promise<TransactionResult>;
  claimRevenue(epoch: bigint): Promise<TransactionResult>;
  buyShares(amount: bigint): Promise<TransactionResult>;
  redeemShares(amount: bigint): Promise<TransactionResult>;
}
```

---

## Appendix A: Event Definitions

```cairo
#[event]
#[derive(Drop, starknet::Event)]
enum Event {
    // Membership
    MemberInvited: MemberInvited,
    MemberJoined: MemberJoined,
    MemberKicked: MemberKicked,
    MemberLeft: MemberLeft,
    MemberRoleChanged: MemberRoleChanged,
    InviteExpired: InviteExpired,

    // Roles
    RoleCreated: RoleCreated,
    RoleModified: RoleModified,
    RoleDeleted: RoleDeleted,

    // Treasury
    CoreActionExecuted: CoreActionExecuted,
    PluginActionExecuted: PluginActionExecuted,
    PluginRegistered: PluginRegistered,
    PluginToggled: PluginToggled,

    // Revenue
    EpochFinalized: EpochFinalized,
    PlayerRevenueClaimed: PlayerRevenueClaimed,
    ShareholderRevenueClaimed: ShareholderRevenueClaimed,
    DistributionPolicyChanged: DistributionPolicyChanged,

    // Shares
    ShareOfferCreated: ShareOfferCreated,
    SharesPurchased: SharesPurchased,
    SharesRedeemed: SharesRedeemed,

    // Inactivity
    InactivityFlagged: InactivityFlagged,
    InactivityCleared: InactivityCleared,

    // Lifecycle
    GuildDissolved: GuildDissolved,
}
```

---

## Appendix B: Implementation Order (PR Stack)

| # | Branch | Scope | Dependencies |
|---|--------|-------|--------------|
| 1 | `feat/dev-env` | Nix + Scarb + OZ 3.0.0 setup | — |
| 2 | `feat/data-model` | Structs, interfaces, events, constants | 1 |
| 3 | `feat/permission-system` | `_check_permission`, `_only_governor`, spending limits | 2 |
| 4 | `feat/guild-lifecycle` | Invite/accept/kick/leave/promote/dissolve | 3 |
| 5 | `feat/guild-token` | ERC20Votes, activity tracking, inactivity, ping | 2 |
| 6 | `feat/governor` | OZ Governor wiring, proposal execution | 5 |
| 7 | `feat/treasury` | Core actions, plugin system, PonziLand helpers | 3 |
| 8 | `feat/revenue` | Distribution policy, epochs, claims, shares, redemption | 7, 5 |
| 9 | `feat/factory` | GuildFactory, registry, uniqueness | All above |
| 10 | `feat/e2e` | E2E integration tests, template guilds | All above |

---

## Appendix C: Migration from v0.1

### Breaking Changes from v0.1

| v0.1 | v0.2 | Reason |
|------|------|--------|
| `Rank` struct with bool fields | `Role` struct with bitmask `allowed_actions` | More flexible, extensible |
| `owner` field (EOA control) | Governor-only admin | Decentralization |
| `is_creator` on Member | Role 0 = founder role | Cleaner abstraction |
| No events | Full event coverage | Indexability |
| No spending limits | Per-role `spending_limit` | Treasury security |
| No revenue distribution | Epoch-based claims | Economic model |
| No share offerings | ShareOffer + RedemptionWindow | Capital formation |
| DUMMY_TOKEN_ADDRESS fallback | Token always deployed via factory | Proper deployment |

---

## Appendix D: OpenZeppelin Cairo 3.0.0 API Reference

### D.1 ERC20VotesComponent

```cairo
// Import
use openzeppelin_token::erc20::extensions::ERC20VotesComponent;

// IVotes trait (embeddable)
fn get_votes(self: @TState, account: ContractAddress) -> u256;
fn get_past_votes(self: @TState, account: ContractAddress, timepoint: u64) -> u256;
fn get_past_total_supply(self: @TState, timepoint: u64) -> u256;
fn delegates(self: @TState, account: ContractAddress) -> ContractAddress;
fn delegate(ref self: TState, delegatee: ContractAddress);
fn delegate_by_sig(ref self: TState, delegator: ContractAddress, delegatee: ContractAddress, nonce: felt252, expiry: u64, signature: Array<felt252>);

// Internal functions
fn transfer_voting_units(ref self, from: ContractAddress, to: ContractAddress, amount: u256);
fn num_checkpoints(self: @, account: ContractAddress) -> u32;
fn checkpoints(self: @, account: ContractAddress, pos: u32) -> Checkpoint;
fn get_voting_units(self: @, account: ContractAddress) -> u256;
```

**Critical**: Requires `ERC20HooksTrait` implementation to sync voting units:
```cairo
impl ERC20VotesHooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {
    fn after_update(ref self: ERC20Component::ComponentState<ContractState>,
        from: ContractAddress, recipient: ContractAddress, amount: u256) {
        let mut votes = get_dep_component_mut!(ref self, ERC20Votes);
        votes.transfer_voting_units(from, recipient, amount);
    }
}
```

**Dependencies**: ERC20Component, NoncesComponent, SNIP12Metadata

### D.2 GovernorComponent

```cairo
// Import
use openzeppelin_governance::governor::GovernorComponent;

// Core functions (IGovernor)
fn propose(ref self, calls: Span<Call>, description: ByteArray) -> felt252;
fn queue(ref self, calls: Span<Call>, description_hash: felt252) -> felt252;
fn execute(ref self, calls: Span<Call>, description_hash: felt252) -> felt252;
fn cancel(ref self, calls: Span<Call>, description_hash: felt252) -> felt252;
fn cast_vote(ref self, proposal_id: felt252, support: u8) -> u256;
fn cast_vote_with_reason(ref self, proposal_id: felt252, support: u8, reason: ByteArray) -> u256;

// Query functions
fn state(self: @, proposal_id: felt252) -> ProposalState;
fn proposal_snapshot(self: @, proposal_id: felt252) -> u64;
fn proposal_deadline(self: @, proposal_id: felt252) -> u64;
fn proposal_proposer(self: @, proposal_id: felt252) -> ContractAddress;
fn has_voted(self: @, proposal_id: felt252, account: ContractAddress) -> bool;
```

**Required extension traits** (must be implemented for GovernorComponent to work):

| Trait | Implementation Component |
|-------|-------------------------|
| `GovernorSettingsTrait` | `GovernorSettingsComponent` — voting_delay, voting_period, proposal_threshold |
| `GovernorQuorumTrait` | `GovernorVotesQuorumFractionComponent` — quorum as fraction of total supply |
| `GovernorCountingTrait` | `GovernorCountingSimpleComponent` — For/Against/Abstain counting |
| `GovernorVotesTrait` | `GovernorVotesComponent` — reads voting power from token |
| `GovernorExecutionTrait` | `GovernorTimelockExecutionComponent` — timelock-gated execution |

**VoteType enum**: Against=0, For=1, Abstain=2

**QuorumFraction**: denominator is 1000, so quorum_numerator=100 = 10% quorum

### D.3 TimelockControllerComponent

```cairo
// Import
use openzeppelin_governance::timelock::TimelockControllerComponent;

// Roles
pub const PROPOSER_ROLE: felt252 = selector!("PROPOSER_ROLE");
pub const EXECUTOR_ROLE: felt252 = selector!("EXECUTOR_ROLE");
pub const CANCELLER_ROLE: felt252 = selector!("CANCELLER_ROLE");

// Key functions
fn schedule(ref self, call: Call, predecessor: felt252, salt: felt252, delay: u64);
fn schedule_batch(ref self, calls: Span<Call>, predecessor: felt252, salt: felt252, delay: u64);
fn execute(ref self, call: Call, predecessor: felt252, salt: felt252);
fn execute_batch(ref self, calls: Span<Call>, predecessor: felt252, salt: felt252);
fn cancel(ref self, id: felt252);
fn get_min_delay(self: @) -> u64;

// Initializer
fn initializer(ref self, min_delay: u64, proposers: Span<ContractAddress>,
    executors: Span<ContractAddress>, admin: ContractAddress);
```

**Dependencies**: AccessControlComponent, SRC5Component

### D.4 SRC5Component (Interface Detection)

```cairo
// Import
use openzeppelin_introspection::src5::SRC5Component;

// Interface
fn supports_interface(self: @, interface_id: felt252) -> bool;

// Internal
fn register_interface(ref self, interface_id: felt252);
fn deregister_interface(ref self, interface_id: felt252);
```

### D.5 Design Decision: Custom Bitmask vs OZ AccessControl

We use a **custom bitmask permission system** rather than OZ AccessControl because:
- Gas efficiency: 1 storage read + bitwise AND vs 2 reads
- Domain fit: Roles map directly to guild membership hierarchy
- Extensibility: Plugin action bits are naturally encoded in the bitmask
- Simplicity: No role-admin hierarchy needed (Governor is sole admin)

We DO use SRC5Component for standard interface detection.

### D.6 Component Composition Pattern

```cairo
#[starknet::contract]
mod MyContract {
    // 1. Declare components
    component!(path: SomeComponent, storage: some, event: SomeEvent);

    // 2. Embed implementations
    #[abi(embed_v0)]
    impl SomeImpl = SomeComponent::SomeImpl<ContractState>;

    // 3. Storage with substorage
    #[storage]
    struct Storage {
        #[substorage(v0)]
        some: SomeComponent::Storage,
    }

    // 4. Events with flat
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SomeEvent: SomeComponent::Event,
    }
}
```
