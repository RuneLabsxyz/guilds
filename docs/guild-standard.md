# Guild Contract Standard

## Purpose

Defines the expected interface, behaviors, and permission checks for a decentralized guild contract on Starknet.

## Member Management

- **invite_member(address)**: Only the owner or members with can_invite permission can invite new members. Fails if the address is already a member.
- **kick_member(address)**: Only the owner or members with can_kick permission can remove members. Fails if the target is not a member or cannot be kicked.

## Rank System

- **Ranks**: Each member is assigned a rank (by rank_id). Each rank defines:
  - can_invite: Can invite new members
  - can_kick: Can kick other members
  - promote: How many ranks below they can promote
  - can_be_kicked: Whether this rank can be kicked
- **create_rank(name, can_invite, can_kick, promote, can_be_kicked)**: Only owner can create new ranks.
- **delete_rank(rank_id)**: Only owner can delete ranks (except creator's rank).
- **change_rank_permissions(rank_id, ...)**: Only owner can change rank permissions.

## Metadata

- **get_guild_name()**: Returns the guild name.
- **get_owner()**: Returns the owner address.
- **max_rank()**: Returns the number of ranks defined.

## Error Handling

- All actions must revert with clear error messages if permission or existence checks fail.
- Special cases (e.g., cannot kick the creator) must be enforced.

## Method Signatures (Example)

```cairo
fn invite_member(ref self: ComponentState<TContractState>, member: ContractAddress);
fn kick_member(ref self: ComponentState<TContractState>, member: ContractAddress);
fn create_rank(ref self: ComponentState<TContractState>, ...);
fn delete_rank(ref self: ComponentState<TContractState>, rank_id: u8);
fn change_rank_permissions(ref self: ComponentState<TContractState>, ...);
```

## Best Practices

- Always check permissions before mutating state.
- Use clear, descriptive error messages.
- Ensure test coverage for all permission and edge cases.
