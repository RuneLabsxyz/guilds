# Contract Guidelines Checklist

| Guideline Item | Pass/Fail | Evidence (File/Test/Commit) | Remediation PR |
| --- | --- | --- | --- |
| Access control boundaries on privileged paths | Pass | `src/guild/guild_contract.cairo` (`_only_governor`, `_check_permission`), `tests/test_permissions.cairo`, commit `dd5f53d` | - |
| Initialization safety (single init assumptions) | Pass | `src/guild/guild_contract.cairo` initialization wiring, `src/token/guild_token.cairo` constructor wiring, `tests/test_lifecycle.cairo` | - |
| Duplicate entrypoint prevention | Pass | Interface split in `src/interfaces/*.cairo`, contracts compile target in `Scarb.toml`, CI workflow `.github/workflows/_test-contracts.yaml` | - |
| Storage read/write trait correctness | Pass | `starknet::Store` derivations in `src/models/types.cairo`, storage read/write patterns in `src/guild/guild_contract.cairo`, `src/token/guild_token.cairo` | - |
| Assert/message conventions compatible with toolchain | Pass | Felt-based error constants in `src/guild/guild_contract.cairo` (`mod Errors`), negative-path tests in `tests/test_*` | - |
| Numeric bounds / felt range safety | Pass | Action bounds checks in `src/guild/guild_contract.cairo` (plugin offset overflow and BPS sum checks), tests in `tests/test_revenue.cairo` | - |
| Deterministic error paths | Pass | Centralized error constants in `src/guild/guild_contract.cairo`, `#[should_panic]` assertions across tests | - |
| Invariant preservation under edge cases | Pass | Lifecycle, treasury, token inactivity, and revenue edge cases in `tests/test_lifecycle.cairo`, `tests/test_treasury.cairo`, `tests/test_guild_token.cairo`, `tests/test_revenue.cairo` | - |
| Event emissions for indexability | Pass | Event models in `src/models/events.cairo`, emission points in `src/guild/guild_contract.cairo`, tests covering state transitions | - |
| Factory lifecycle implementation completeness | Pass | Implementation at `src/factory/guild_factory.cairo`, exports in `src/lib.cairo`, coverage in `tests/test_factory.cairo`, commit `5b6fd20` | - |

## Notes

- This checklist is release-gating documentation.
- A `Fail` item blocks final production-go unless explicitly accepted as a limitation.
- If a new contract/security guideline is introduced, add a new row with evidence before merge.
