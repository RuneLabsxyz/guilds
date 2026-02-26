import { GuildsSdkError } from '../errors/index.js';
import type { StarknetAddress } from '../types/contracts.js';

export function isHexAddress(value: string): value is StarknetAddress {
  return /^0x[0-9a-fA-F]+$/.test(value) && value.length >= 4;
}

export function assertAddress(value: string, fieldName: string): StarknetAddress {
  if (!isHexAddress(value)) {
    throw new GuildsSdkError('INVALID_INPUT', `Invalid address for ${fieldName}: ${value}`);
  }
  return value;
}
