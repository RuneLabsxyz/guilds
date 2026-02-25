# PonziLand Guilds Specifications (v0.1)

Welcome to the **PonziLand Guilds** module—designed to introduce social, political, and economic dynamics through onchain guilds.

---

## 🔗 Quick Links

- **Website:** https://www.ponzi.land  
- **Runelabs:** https://www.runelabs.xyz  
- **Discord:** https://discord.gg/ponziland  
- **Twitter (PonziDotLand):** https://x.com/ponzidotland  
- **Twitter (RuneLabsxyz):** https://x.com/runelabsxyz

---

## 🎯 Objectives

1. **Facilitate social community formation** inside the game
2. **Introduce competitive and political narratives** via guild dynamics
3. **Enable economic access and mobility** for smaller or new players
4. **Support team-based esports** with in‑game guild competitions

*Guilds function as a DAO, an investment fund, and an esports team.*

---

## 🛠️ Basic Features

### Creating a Guild

- **Capital requirement:** Player must deposit a minimum capital (e.g. $10) at creation.
  - 1000 shares are minted; initial share value = capital / 1000.
- **Metadata:**
  - **Logo:** Generated via in‑game pattern designer and minted on-chain.
  - **Guild name:** 4–50 chars; letters, numbers, spaces, dots; unique among active guilds.
  - **Ticker:** 1–5 chars; letters, numbers, spaces, dots; globally unique.
  - **Description:** Up to 4,000 characters (editable).
- **Governance settings:** Default profit distribution and role‑based rules set by CEO at creation.

### Closing a Guild

- All members must leave or be removed.
- CEO must resign to trigger on-chain guild closure.
- A liquidation has been voted.

### Joining a Guild

| Type           | Behavior                                                                                     |
| -------------- | -------------------------------------------------------------------------------------------- |
| **Public**     | Instant join; optional soft filters (level, experience).                                     |
| **Private**    | Players submit join request with optional message.                                           |
| **Invitation** | Officers send direct invites; bypass request queue.                                          |
| **Management** | Officers can approve, reject, or blacklist; Master toggles recruitment status.               |

### Player Management

- **Roles & Permissions:** Kick, ban, promote/demote
- **Request Handling:** Approve, reject, blacklist

### Season Scoring & Standings

Track guild performance metrics each season:

- Sum of player scores
- Total land owned & assets
- Stakes and supply metrics
- Leaderboard positions

---

## 💰 Economic Structure

Guilds manage shared capital via an on-chain share system:

1. **Capital Building:** CEO deposits base capital; 1000 ERC‑20 shares minted.
2. **Shareholding:** Players buy shares via on-chain rounds.
3. **Voting:** Share count = voting power; used for share emissions and rate changes.
4. **Emitting Shares:** 51% shareholder approval; public purchase round with proportional allocation.

### Capital Distribution & Yield

- Guild owns a portfolio of tokens as idle capital.
- Objective: maximize ROI by allocating to productive players.

---

## 🏛️ Guild Roles & Wallets

| Role           | Description                                                                                       |
| -------------- | ------------------------------------------------------------------------------------------------- |
| **Guild Master** | Elected CEO; sole issuer of major proposals; controls master wallet.                             |
| **Co‑Leader**    | Second‑in‑command; assists Master; accesses high‑tier wallet.                                   |
| **Officer**      | Manages membership, requests; accesses mid‑tier wallet.                                        |
| **Member**       | Standard participant; accesses member wallet.                                                  |
| **Recruit**      | Trial role; limited permissions; no wallet access.                                            |

- **Guild Wallets:** Five on-chain wallets, each gated by role for capital allocation and payouts.

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
