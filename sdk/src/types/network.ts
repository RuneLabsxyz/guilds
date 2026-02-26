import type { StarknetAddress } from './contracts.js';

export type GuildsNetwork = 'mainnet' | 'sepolia' | 'local';

export interface NetworkAddressBook {
  factory?: StarknetAddress;
  guildTemplate?: StarknetAddress;
  tokenTemplate?: StarknetAddress;
  governorTemplate?: StarknetAddress;
}

export interface GuildsClientOptions {
  network: GuildsNetwork;
  addresses?: NetworkAddressBook;
  retry?: {
    attempts?: number;
    initialDelayMs?: number;
    maxDelayMs?: number;
    backoffMultiplier?: number;
  };
}
