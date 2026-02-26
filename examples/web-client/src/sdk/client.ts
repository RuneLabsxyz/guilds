import { createGuildsClient, type ContractTransport, type GuildsClient, type GuildsNetwork } from '@runelabsxyz/guilds-sdk';

export interface InvokeLog {
  contractAddress: string;
  entrypoint: string;
  calldata: readonly string[];
  transactionHash: string;
  createdAtIso: string;
}

export interface MockState {
  readonly invokes: readonly InvokeLog[];
}

const GUILD_RESULT = ['0x111', '0x222', '0x333'] as const;

class BrowserMockTransport implements ContractTransport {
  private invokes: InvokeLog[] = [];

  public async call<T = string[]>(request: {
    contractAddress: string;
    entrypoint: string;
    calldata: readonly string[];
  }): Promise<T> {
    if (request.entrypoint === 'get_guild') {
      return [...GUILD_RESULT] as T;
    }

    if (request.entrypoint === 'get_governor_address') {
      return ['0x333'] as T;
    }

    if (request.entrypoint === 'get_token_address') {
      return ['0x222'] as T;
    }

    return ['0x0'] as T;
  }

  public async invoke(request: {
    contractAddress: string;
    entrypoint: string;
    calldata: readonly string[];
    maxFee?: bigint;
  }): Promise<{ transactionHash: string }> {
    const transactionHash = `0xmock${(this.invokes.length + 1).toString(16).padStart(8, '0')}`;
    this.invokes = [
      {
        contractAddress: request.contractAddress,
        entrypoint: request.entrypoint,
        calldata: request.calldata,
        transactionHash,
        createdAtIso: new Date().toISOString(),
      },
      ...this.invokes,
    ];
    return { transactionHash };
  }

  public getState(): MockState {
    return { invokes: this.invokes };
  }
}

export interface BrowserClientBundle {
  readonly client: GuildsClient;
  readonly transport: BrowserMockTransport;
}

export function createBrowserClientBundle(network: GuildsNetwork, factory: `0x${string}`): BrowserClientBundle {
  const transport = new BrowserMockTransport();
  const client = createGuildsClient(transport, {
    network,
    addresses: { factory },
    retry: { attempts: 1 },
  });

  return { client, transport };
}
