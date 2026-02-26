# @runelabsxyz/guilds-sdk

Typed TypeScript SDK for RuneLabs Guilds contracts.

## Quickstart

```bash
npm install @runelabsxyz/guilds-sdk
```

```ts
import { createGuildsClient, type ContractTransport } from '@runelabsxyz/guilds-sdk';

const transport: ContractTransport = {
  call: async () => ['0x1', '0x2', '0x3'],
  invoke: async () => ({ transactionHash: '0xabc' }),
};

const client = createGuildsClient(transport, {
  network: 'sepolia',
  addresses: { factory: '0x1234' },
});
```

## Common Flows

- Create guild: `client.createGuild(...)`
- Register/wire addresses: `client.registerAddresses(...)`
- Governance actions: `client.governanceAction(...)`, `client.vote(...)`
- Treasury and token interactions: `client.treasuryAction(...)`, `client.buyShares(...)`, `client.redeemShares(...)`

## Compatibility Gate

```bash
npm run check:compat
```

This command fails if Cairo interface signatures changed without updating `sdk/generated/contracts.signature.json`.
