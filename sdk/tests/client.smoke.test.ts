import { describe, expect, it } from 'vitest';

import { createGuildsClient } from '../src/client/create-client.js';
import type { CreateGuildParams } from '../src/types/contracts.js';
import { MockTransport } from './helpers/mock-transport.js';

describe('guilds client smoke', () => {
  it('creates guild and resolves addresses via transport', async () => {
    const transport = new MockTransport();
    transport.setCallResponse(['0x111', '0x222', '0x333']);

    const client = createGuildsClient(transport, {
      network: 'local',
      addresses: { factory: '0xabc' },
      retry: { attempts: 1 },
    });

    const params: CreateGuildParams = {
      name: 'GuildOne',
      ticker: 'G1',
      depositToken: '0xdef',
      depositAmount: 10n,
      initialTokenSupply: 1_000n,
      governorConfig: {
        votingDelay: 1n,
        votingPeriod: 10n,
        proposalThreshold: 1n,
        quorumBps: 1000,
        timelockDelay: 1n,
      },
    };

    const tx = await client.createGuild(params);
    expect(tx.transactionHash).toBe('0xabc123');
    expect(transport.invokes[0]?.entrypoint).toBe('create_guild');

    const addresses = await client.resolveGuildAddresses('0x111');
    expect(addresses.guild).toBe('0x111');
    expect(addresses.token).toBe('0x222');
    expect(addresses.governor).toBe('0x333');
  });
});
