# Guild Ranks Design

## Purpose

The rank system enables fine-grained, role-based access control within a guild. Each member is assigned a rank, and each rank encodes a set of permissions. **Only rank management (create, delete, change permissions) is governed by token-holder voting.**

## Rank Structure

- **rank_name (felt252)**: Human-readable name for the rank.
- **can_invite (bool)**: Whether members of this rank can invite new members.
- **can_kick (bool)**: Whether members of this rank can kick others.
- **promote (u8)**: How many ranks below this one the member can promote.
- **can_be_kicked (bool)**: Whether members of this rank can be kicked by others.

## Assignment

- Each member has a `rank_id` pointing to a rank in the ranks map.
- The creator is always assigned rank 0, which by default cannot be kicked.
- Only the governance contract can create, delete, or change rank permissions.
- Members can be promoted/demoted by those with the appropriate rank permissions.

## Permission Logic

- **Rank management (create, delete, change permissions) is only allowed if approved by governance.**
- **Invite, kick, and promote actions are permission-based, controlled by rank permissions.**
- Kicking is only allowed if the target's rank has `can_be_kicked = true`.

## Example

```cairo
// Example: Proposing a new rank (via governance)
// governance.propose_create_rank(name, can_invite, can_kick, promote, can_be_kicked)

// Assigning a rank to a member (permission-based)
// state.promote_member(addr, new_rank_id) // if caller has promote permission
```

## Best Practices

- Use descriptive names for ranks.
- Set `can_be_kicked = false` for high-privilege roles (e.g., creator, admin).
- Regularly review and test rank permissions to ensure security.
- Avoid circular or ambiguous promotion logic.
- Ensure all changes to rank structure are transparent and auditable via governance proposals.
