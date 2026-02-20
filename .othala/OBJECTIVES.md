# Guilds Objectives (Othala)

## Primary goal
Ship contract-complete Guilds v0.1 core loop with strong tests before SDK expansion.

## Top priorities
1. Governance-first delegation framework for all sensitive actions.
2. Role/permission model where role bypass is possible only after governance-approved grants.
3. Share lifecycle management including inactive/dormant share handling (incl. destroy/burn policy where needed).
4. Investor share model and protections.
5. Dual revenue engine:
   - share-based investor revenue
   - guild member performance-based revenue
   with strict accounting invariants.
6. Guild creation + metadata constraints + uniqueness checks.
7. Membership pipeline (public/private/invite, moderation, blacklist).
8. Season scoring primitives for guild standings.
9. After contracts are stable and tested: SDK v0 for game integration (PonziLand first, game-agnostic design).

## Quality bar
- Contract tests required for each feature increment.
- Prefer short vertical slices that compile + pass tests.
- Keep state transitions explicit and auditable.

## Othala mode
- repo-mode: merge
- verify command: sozo test || scarb test
