# Guild Ranks Design

## Purpose

The rank system enables fine-grained, role-based access control within a guild. Each member is assigned a rank, and each rank encodes a set of permissions.

## Rank Structure

- **rank_name (felt252)**: Human-readable name for the rank.
- **can_invite (bool)**: Whether members of this rank can invite new members.
- **can_kick (bool)**: Whether members of this rank can kick others.
- **promote (u8)**: How many ranks below this one the member can promote.
- **can_be_kicked (bool)**: Whether members of this rank can be kicked by others.

## Assignment

- Each member has a `rank_id` pointing to a rank in the ranks map.
- The creator is always assigned rank 0, which by default cannot be kicked.

## Permission Logic

- Actions (invite, kick, promote) are only allowed if the caller's rank has the corresponding permission.
- Kicking is only allowed if the target's rank has `can_be_kicked = true`.
- Only the owner can create, delete, or modify ranks.

## Example

```cairo
// Example: Creating a new rank
state.create_rank(123, true, false, 1, true); // Name=123, can_invite=true, can_kick=false, promote=1, can_be_kicked=true

// Assigning a rank to a member
let mut member = state.members.read(addr);
member.rank_id = new_rank_id;
state.members.write(addr, member);
```

## Best Practices

- Use descriptive names for ranks.
- Set `can_be_kicked = false` for high-privilege roles (e.g., creator, admin).
- Regularly review and test rank permissions to ensure security.
- Avoid circular or ambiguous promotion logic.
