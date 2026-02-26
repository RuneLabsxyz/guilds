import { describe, expect, it } from 'vitest';

import { withRetry } from '../src/utils/retry.js';

describe('retry', () => {
  it('retries and eventually succeeds', async () => {
    let attempts = 0;
    const result = await withRetry(
      'eventual',
      async () => {
        attempts += 1;
        if (attempts < 3) {
          throw new Error('temporary');
        }
        return 'ok';
      },
      {
        attempts: 3,
        initialDelayMs: 1,
        maxDelayMs: 2,
        backoffMultiplier: 1,
      },
    );

    expect(result).toBe('ok');
    expect(attempts).toBe(3);
  });
});
