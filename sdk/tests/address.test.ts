import { describe, expect, it } from 'vitest';

import { assertAddress, isHexAddress } from '../src/utils/address.js';

describe('address utils', () => {
  it('validates hex addresses', () => {
    expect(isHexAddress('0x1234')).toBe(true);
    expect(isHexAddress('0xabcdef')).toBe(true);
    expect(isHexAddress('not-an-address')).toBe(false);
  });

  it('throws for invalid address input', () => {
    expect(() => assertAddress('bad', 'factory')).toThrow('Invalid address');
  });
});
