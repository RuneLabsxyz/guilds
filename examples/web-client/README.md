# Guilds SDK Web Client Example

Browser playground for the Guilds SDK.

## Run

```bash
cd examples/web-client
npm install
npm run dev
```

## Verify

```bash
npm run typecheck
npm run build
```

This app currently uses an in-browser mock transport so flows can be exercised without a wallet during development.

## Included Flows

- Create guild with SDK `createGuild` and display resolved guild/token/governor addresses.
- Governance proposal todo list using `governanceAction` and per-item vote actions via `vote`.
- Treasury send money and get approval actions via `treasuryAction` (`transfer` and `approve` modes).
