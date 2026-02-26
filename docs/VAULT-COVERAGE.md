# Vault Coverage Matrix

Canonical requirement source: `/home/mugen/Documents/Obsidian Vault/life/areas/projects/guilds.md`.

| Vault Requirement | Task/PR | Status | Test Coverage | Merged Commit |
| --- | --- | --- | --- | --- |
| Governance-first delegation model | `feat/guild-lifecycle`, `feat/governor`, `feat/permission-system` | Implemented | `tests/test_lifecycle.cairo`, `tests/test_guild_governor.cairo`, `tests/test_permissions.cairo` | `f862363`, `b58d212`, `dd5f53d` |
| Role framework and bypass boundaries | `feat/permission-system` | Implemented | `tests/test_permissions.cairo`, `tests/test_lifecycle.cairo` | `dd5f53d`, `f862363` |
| Share lifecycle and inactivity handling | `feat/guild-token`, `feat/revenue` | Implemented | `tests/test_guild_token.cairo`, `tests/test_revenue.cairo` | `91607db`, `2370af8` |
| Dual revenue model (shareholder + member) | `feat/revenue` | Implemented | `tests/test_revenue.cairo` | `2370af8` |
| End-to-end governance to execution paths | `feat/governor`, `feat/treasury`, `feat(factory)` | Implemented | `tests/test_guild_governor.cairo`, `tests/test_treasury.cairo`, `tests/test_factory.cairo` | `b58d212`, `486b922`, `5b6fd20` |
| SDK v0 scaffold after contract hardening | `feat(sdk): production scaffold` | Implemented | `sdk/tests/address.test.ts`, `sdk/tests/retry.test.ts`, `sdk/tests/client.smoke.test.ts` | `7b6cb98`, `f2f56c9` |

## Coverage Notes

- Local stack commits listed above become merge commits after stack submission.
- This matrix must be updated in every cycle that changes contracts, SDK interfaces, or vault requirements.
- SDK compatibility gate is enforced by `sdk/scripts/check-contract-compat.mjs` and snapshot file `sdk/generated/contracts.signature.json`.
