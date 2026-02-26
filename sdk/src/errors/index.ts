export type GuildsSdkErrorCode =
  | 'INVALID_INPUT'
  | 'NETWORK_MISMATCH'
  | 'MISSING_ADDRESS'
  | 'TRANSPORT_ERROR'
  | 'CONTRACT_CALL_FAILED'
  | 'RETRY_EXHAUSTED'
  | 'CONFIG_ERROR';

export class GuildsSdkError extends Error {
  public readonly code: GuildsSdkErrorCode;
  public readonly details?: unknown;

  public constructor(code: GuildsSdkErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = 'GuildsSdkError';
    this.code = code;
    this.details = details;
  }
}

export function toGuildsSdkError(error: unknown, fallback: GuildsSdkErrorCode): GuildsSdkError {
  if (error instanceof GuildsSdkError) {
    return error;
  }
  const message = error instanceof Error ? error.message : 'Unknown SDK error';
  return new GuildsSdkError(fallback, message, error);
}
