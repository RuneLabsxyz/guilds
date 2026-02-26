# Release Readiness Report

## Checklist

- [x] Graphite stack repair and operator scripts added (`scripts/operator/repair-graphite-stack.sh`, `46ef136`)
- [x] QA self-heal loop added (`scripts/operator/qa-self-heal.sh`, `46ef136`)
- [x] Contract test workflow exists (`.github/workflows/_test-contracts.yaml`, `46ef136`)
- [x] SDK scaffold implemented (`sdk/`, `7b6cb98`, `f2f56c9`)
- [x] Vault coverage matrix added (`docs/VAULT-COVERAGE.md`)
- [x] Contract guidelines checklist added (`docs/CONTRACT-GUIDELINES-CHECKLIST.md`)
- [x] Factory lifecycle implementation completed (`src/factory/guild_factory.cairo`, `tests/test_factory.cairo`, `5b6fd20`)

## Known Limitations

1. Local environment must provide Scarb/Snforge/USC toolchain (or Nix shells + binaries) for deterministic contract verification.

## Migration Notes

- Existing contracts follow v0.2 data model and permission boundaries (`5060c00`, `dd5f53d`, `f862363`, `91607db`, `b58d212`, `486b922`, `2370af8`).
- SDK introduces compatibility checks against Cairo interface signatures (`sdk/generated/contracts.signature.json`).
- Any interface changes now require `npm run sync:contracts` in `sdk/`.

## Test Matrix (Current)

| Scope | Command | Expected Result |
| --- | --- | --- |
| Cairo fmt + test | `scarb fmt --check --workspace && snforge test` | pass |
| Fallback verify | `sozo test || scarb test` | pass |
| SDK type checks | `npm run typecheck && npm run typecheck:examples` (in `sdk/`) | pass |
| SDK compatibility gate | `npm run check:compat` (in `sdk/`) | pass |
| SDK tests | `npm run test` (in `sdk/`) | pass |

## Operator Mode

Run from repo root:

```bash
./scripts/operator/repair-graphite-stack.sh
./scripts/operator/qa-self-heal.sh
```

- `repair-graphite-stack.sh` tracks untracked branches, restacks iteratively, and clears metadata cache as fallback.
- `qa-self-heal.sh` loops verify, creates deduplicated fix tasks in `.operator/tasks/`, and exits green only when verify passes.

## Go/No-Go

- **Current recommendation:** **GO** after stack submit/merge and one final CI green pass.
- **Hardening window (next 7 days):** reduce deprecated `contract_address_const` usage warnings and remove stale unused imports in legacy modules.
