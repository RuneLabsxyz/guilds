# Guilds Objectives (Othala)

## Primary goal
Ship contract-complete Guilds v0.1 core loop with strong tests before SDK expansion.

## Top priorities
1. Guild creation + metadata constraints + uniqueness checks.
2. Membership pipeline (public/private/invite, moderation, blacklist).
3. Role/permission model and wallet access boundaries.
4. Shares, voting, and emission proposal mechanics.
5. Profit distribution invariants (players/treasury/shareholders).
6. Season scoring primitives for guild standings.

## Quality bar
- Contract tests required for each feature increment.
- Prefer short vertical slices that compile + pass tests.
- Keep state transitions explicit and auditable.

## Othala mode
- repo-mode: merge
- verify command: sozo test || scarb test
