# Guild Contract Standard

## Purpose

Defines the expected interface, behaviors, and permission checks for a decentralized guild contract on Starknet. **Only rank management (create, delete, change permissions) is governed by token-holder voting.**

## Member Management

- **invite_member(address)**: Members with can_invite permission can invite new members. Fails if the address is already a member.
- **kick_member(address)**: Members with can_kick permission can remove members. Fails if the target is not a member or cannot be kicked.

## Rank System

- **Ranks**: Each member is assigned a rank (by rank_id). Each rank defines:
  - can_invite: Can invite new members
  - can_kick: Can kick other members
  - promote: How many ranks below they can promote
  - can_be_kicked: Whether this rank can be kicked
- **create_rank(name, can_invite, can_kick, promote, can_be_kicked)**: Only via governance proposal.
- **delete_rank(rank_id)**: Only via governance proposal (except creator's rank).
- **change_rank_permissions(rank_id, ...)**: Only via governance proposal.

## ERC20 Equity

- **mint(to, amount)**: Only via governance proposal.
- **burn(from, amount)**: Only via governance proposal (e.g., for inactivity).
- **transfer, approve, etc.**: Standard ERC20 endpoints.

## Governance

- **propose(action, params)**: Any token holder can propose an action (e.g., add rank, change permissions, mint, burn, etc.).
- **vote(proposal_id, support)**: Token holders vote on proposals.
- **execute(proposal_id)**: If passed, proposal is executed (calls into Guild/Equity contracts).
- **inactivity_burn(address)**: Proposal to burn tokens from inactive addresses.

## Metadata

- **get_guild_name()**: Returns the guild name.
- **get_governance()**: Returns the governance contract address.
- **get_equity_token()**: Returns the equity token contract address.
- **max_rank()**: Returns the number of ranks defined.

## Error Handling

- All actions revert with clear error messages if permission or existence checks fail.
- Special cases (e.g., cannot kick the creator) are enforced.

## Method Signatures (Example)

```cairo
fn invite_member(ref self: ComponentState<TContractState>, member: ContractAddress);
fn kick_member(ref self: ComponentState<TContractState>, member: ContractAddress);
fn create_rank(ref self: ComponentState<TContractState>, ...); // governance only
fn delete_rank(ref self: ComponentState<TContractState>, rank_id: u8); // governance only
fn change_rank_permissions(ref self: ComponentState<TContractState>, ...); // governance only
// ERC20: mint, burn, transfer, approve, etc.
// Governance: propose, vote, execute (for rank management)
```

## Best Practices

- All rank management actions require governance approval.
- Invite/kick actions are permission-based.
- Use clear, descriptive error messages.
- Ensure test coverage for all permission and edge cases.
