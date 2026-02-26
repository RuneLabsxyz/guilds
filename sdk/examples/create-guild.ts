import { createGuildsClient, type ContractTransport } from '../src/index.js';

const transport: ContractTransport = {
  call: async <T>() => ['0x111', '0x222', '0x333'] as T,
  invoke: async () => ({ transactionHash: '0xabc123' }),
};

async function main() {
  const client = createGuildsClient(transport, {
    network: 'local',
    addresses: { factory: '0xabc' },
  });

  const tx = await client.createGuild({
    name: 'GuildOne',
    ticker: 'G1',
    depositToken: '0xdef',
    depositAmount: 10n,
    initialTokenSupply: 1_000n,
    governorConfig: {
      votingDelay: 1n,
      votingPeriod: 10n,
      proposalThreshold: 1n,
      quorumBps: 1_000,
      timelockDelay: 1n,
    },
  });

  console.log(tx.transactionHash);
}

void main();
