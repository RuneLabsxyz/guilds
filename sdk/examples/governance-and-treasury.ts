import { createGuildsClient, type ContractTransport } from '../src/index.js';

const transport: ContractTransport = {
  call: async <T>() => ['0x111'] as T,
  invoke: async () => ({ transactionHash: '0xabc123' }),
};

async function main() {
  const client = createGuildsClient(transport, {
    network: 'sepolia',
    addresses: { factory: '0xabc' },
  });

  await client.governanceAction({
    governor: '0x333',
    targets: ['0x111'],
    values: [0n],
    calldatas: ['0x0'],
    description: 'Set policy',
  });

  await client.vote({ governor: '0x333', proposalId: 1n, support: 1 });

  await client.treasuryAction({
    guild: '0x111',
    actionType: 1,
    target: '0x444',
    token: '0x555',
    amount: 50n,
    calldata: [],
  });
}

void main();
