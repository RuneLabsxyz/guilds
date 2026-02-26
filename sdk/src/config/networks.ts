import type { NetworkAddressBook, GuildsNetwork } from '../types/network.js';

export const DEFAULT_NETWORK_ADDRESSES: Record<GuildsNetwork, NetworkAddressBook> = {
  mainnet: {},
  sepolia: {},
  local: {},
};
