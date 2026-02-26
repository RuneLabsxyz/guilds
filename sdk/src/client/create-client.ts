import type { ContractTransport } from '../core/transport.js';
import type { GuildsClientOptions } from '../types/network.js';
import { DefaultGuildsClient, type GuildsClient } from './guilds-client.js';

export function createGuildsClient(transport: ContractTransport, options: GuildsClientOptions): GuildsClient {
  return new DefaultGuildsClient(transport, options);
}
