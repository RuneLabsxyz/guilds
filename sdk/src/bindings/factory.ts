import type { ContractTransport } from '../core/transport.js';
import type { CreateGuildParams, GuildAddresses, StarknetAddress } from '../types/contracts.js';

export interface FactoryBindings {
  createGuild(factory: StarknetAddress, params: CreateGuildParams): Promise<{ transactionHash: string }>;
  getGuild(factory: StarknetAddress, guildAddress: StarknetAddress): Promise<string[]>;
  isNameTaken(factory: StarknetAddress, name: string): Promise<boolean>;
  isTickerTaken(factory: StarknetAddress, ticker: string): Promise<boolean>;
}

function toBool(word: string): boolean {
  return word !== '0x0' && word !== '0';
}

export function createFactoryBindings(transport: ContractTransport): FactoryBindings {
  return {
    async createGuild(factory, params): Promise<{ transactionHash: string }> {
      const calldata = [
        params.name,
        params.ticker,
        params.depositToken,
        `0x${params.depositAmount.toString(16)}`,
        `0x${params.initialTokenSupply.toString(16)}`,
        `0x${params.governorConfig.votingDelay.toString(16)}`,
        `0x${params.governorConfig.votingPeriod.toString(16)}`,
        `0x${params.governorConfig.proposalThreshold.toString(16)}`,
        `0x${params.governorConfig.quorumBps.toString(16)}`,
        `0x${params.governorConfig.timelockDelay.toString(16)}`,
      ];
      return transport.invoke({
        contractAddress: factory,
        entrypoint: 'create_guild',
        calldata,
      });
    },

    async getGuild(factory, guildAddress): Promise<string[]> {
      return transport.call<string[]>({
        contractAddress: factory,
        entrypoint: 'get_guild',
        calldata: [guildAddress],
      });
    },

    async isNameTaken(factory, name): Promise<boolean> {
      const raw = await transport.call<string[]>({
        contractAddress: factory,
        entrypoint: 'is_name_taken',
        calldata: [name],
      });
      return toBool(raw[0] ?? '0x0');
    },

    async isTickerTaken(factory, ticker): Promise<boolean> {
      const raw = await transport.call<string[]>({
        contractAddress: factory,
        entrypoint: 'is_ticker_taken',
        calldata: [ticker],
      });
      return toBool(raw[0] ?? '0x0');
    },
  };
}

export function decodeGuildAddresses(raw: string[]): GuildAddresses {
  return {
    guild: raw[0] as StarknetAddress,
    token: raw[1] as StarknetAddress,
    governor: raw[2] as StarknetAddress,
  };
}
