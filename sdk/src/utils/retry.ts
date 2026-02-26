import { GuildsSdkError, toGuildsSdkError } from '../errors/index.js';

export interface RetryOptions {
  attempts: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffMultiplier: number;
  retryableError?: (error: unknown) => boolean;
}

export const DEFAULT_RETRY_OPTIONS: RetryOptions = {
  attempts: 3,
  initialDelayMs: 150,
  maxDelayMs: 1_000,
  backoffMultiplier: 2,
  retryableError: () => true,
};

export async function withRetry<T>(
  operationName: string,
  fn: () => Promise<T>,
  options: Partial<RetryOptions> = {},
): Promise<T> {
  const cfg: RetryOptions = { ...DEFAULT_RETRY_OPTIONS, ...options };
  let lastError: unknown;
  for (let attempt = 1; attempt <= cfg.attempts; attempt += 1) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      const retryable = cfg.retryableError?.(error) ?? false;
      if (!retryable || attempt === cfg.attempts) {
        break;
      }
      const delay = Math.min(
        cfg.maxDelayMs,
        Math.round(cfg.initialDelayMs * cfg.backoffMultiplier ** (attempt - 1)),
      );
      await new Promise((resolve) => {
        setTimeout(resolve, delay);
      });
    }
  }
  throw new GuildsSdkError(
    'RETRY_EXHAUSTED',
    `Operation '${operationName}' failed after ${cfg.attempts} attempts`,
    toGuildsSdkError(lastError, 'TRANSPORT_ERROR'),
  );
}
