#
#  ____       _ _     _     _      
# / ___|_   _(_) | __| |___| |__   
#| |  _| | | | | |/ _` / __| '_ \  
#| |_| | |_| | | | (_| \__ \ | | | 
# \____|\__,_|_|_|\__,_|___/_| |_| 
#

# Guilds

Guilds is a contract-first Starknet system for on-chain guild governance, treasury operations, and dual revenue distribution (members + shareholders).

## Architecture

- `src/guild/guild_contract.cairo`: guild core state machine (membership, roles, treasury, revenue, shares)
- `src/token/guild_token.cairo`: ERC20Votes-style guild token with inactivity handling
- `src/governor/guild_governor.cairo`: governance control plane
- `src/models/*`: canonical structs, constants, and events
- `tests/*.cairo`: unit + integration-style coverage by domain
- `sdk/`: typed TypeScript SDK with compatibility gate and smoke tests

## Quickstart

### Contracts

```bash
# Option A: use your existing local Scarb/Snforge install
scarb fmt --check --workspace
snforge test

# Option B: project verify fallback
bash -lc 'sozo test || scarb test'
```

### SDK

```bash
cd sdk
npm install
npm run verify
```

## Deployment / Stack Flow

Guilds uses Graphite stack workflows for incremental contract delivery.

```bash
gt create -m "feat(guilds): <scope>"
gt restack --upstack --no-interactive
gt submit --stack --no-interactive
```

Operator scripts:

- `scripts/operator/repair-graphite-stack.sh`: detects/tracks untracked branches, restacks with fallback
- `scripts/operator/qa-self-heal.sh`: verify-loop with deduplicated failure task generation

## Test & Verify Flow

- Contracts: `scarb fmt --check --workspace && snforge test`
- Fallback verify: `sozo test || scarb test`
- SDK type + compat + tests + build: `cd sdk && npm run verify`

## SDK (TS, Production-Oriented)

Package: `@runelabsxyz/guilds-sdk`

- Typed client API (`core/client/types/utils/errors/config/bindings`)
- Contract compatibility gate via `sdk/generated/contracts.signature.json`
- Deterministic error model (`GuildsSdkError` with fixed error codes)
- Retry support for transport operations
- Example flows in `sdk/examples/`

Common flows:

1. Create guild
2. Register/wire addresses
3. Governance action + vote
4. Treasury and token/share operations

## Security Notes

- Governor-only and permission-gated boundaries enforced in guild logic
- Explicit numeric bound checks (BPS sums, plugin action ranges)
- Deterministic panic/error paths for negative scenarios
- Event coverage for indexers (`src/models/events.cairo`)

See `docs/CONTRACT-GUIDELINES-CHECKLIST.md` for itemized evidence.

## Roadmap & Status

- Completed: data model, permissions, lifecycle, token, governor, treasury, revenue
- Completed: SDK productization and operator automation
- Stack integration pending: Graphite stack submit + merge

Vault coverage is tracked in `docs/VAULT-COVERAGE.md`.

## Release Notes Surface

- Release readiness: `docs/RELEASE-READINESS.md`
- SDK changelog: `sdk/CHANGELOG.md`
- Contract spec: `docs/SPEC.md`

## License

---

## 📜 Profit & Rewards

Weekly distribution of guild earnings:

- **50%** to guild players (split by role)
- **30%** retained in treasury
- **20%** to shareholders

**Player breakdown:** Default allocations (modifiable via vote):
- CEO 25%
- Co‑Leaders 25%
- Officers 25%
- Members 25%
- Recruits 0%

Shareholder payouts are proportional to shareholdings.
Master wallet can trigger ad-hoc distributions.

---

## 📁 Repository Structure

- `src/` — core guild contracts (roles, governance, treasury, revenue, lifecycle)
- `tests/` — integration and edge-case suites (snforge)
- `docs/` — protocol and implementation notes
- `.othala/` — orchestration config (merge mode + auto-submit)

---

## 🧪 Client Playground + SDK Spec (v0.2)

### 1) Client Playground (must work end-to-end)
A lightweight playground app/CLI should allow any dev to:
- create guilds with realistic params
- simulate join/invite/blacklist/revoke lifecycle
- execute role-gated treasury actions
- run governance proposals/voting/execution
- simulate revenue epochs, claims, and redemptions
- inspect onchain state transitions and emitted events

**Goal:** reproduce full user journeys without hand-written scripts.

### 2) SDK (game-agnostic)
Provide an SDK that external games can integrate with minimal friction:
- typed client for guild read/write methods
- event/indexing helpers
- action builders for governance and treasury operations
- role/permission capability checks before tx submission
- canonical error mapping and retry semantics

**First integrator:** PonziLand, but API surface should remain generic.

### 3) E2E QA Expectations
QA should verify real behavior, not only compile success.

Required suites:
- **Protocol invariants:** role matrix, governor bypass constraints, dissolved-guild restrictions
- **Lifecycle flows:** create → invite/join → role changes → leave/kick/blacklist → dissolve
- **Governance flows:** propose, vote, quorum checks, execute/defeat timing windows
- **Treasury flows:** transfer/approve/plugin actions with spending limits and permissions
- **Revenue flows:** epoch finalization, split accounting, member vs shareholder claims
- **Adversarial/edge cases:** invalid callers, stale invites, duplicate actions, limit overflow, ordering races

Exit criteria for production readiness:
- green end-to-end flows via snforge suite
- no unresolved high-severity invariants
- deterministic SDK behavior on expected failure paths

---

## 🤝 Contributing

Contributions welcome! Fork, branch, code, test, and submit a PR. Follow code standards and add tests for new logic.

---

## 📄 License

MIT. See [LICENSE](LICENSE) for details.
