import { createFactoryBindings, decodeGuildAddresses } from '../bindings/factory.js';
import { createGuildBindings, wireAddresses } from '../bindings/guild.js';
import type { FactoryBindings } from '../bindings/factory.js';
import type { GuildBindings } from '../bindings/guild.js';
import type { ContractTransport } from '../core/transport.js';
import { DEFAULT_NETWORK_ADDRESSES } from '../config/networks.js';
import { GuildsSdkError, toGuildsSdkError } from '../errors/index.js';
import type {
  CreateGuildParams,
  GovernanceActionParams,
  GuildAddresses,
  ShareActionParams,
  StarknetAddress,
  TreasuryActionParams,
  VoteParams,
  WireGuildAddressesParams,
} from '../types/contracts.js';
import type { GuildsClientOptions } from '../types/network.js';
import type { GuildsNetwork } from '../types/network.js';
import { assertAddress } from '../utils/address.js';
import { withRetry } from '../utils/retry.js';

export interface GuildsClient {
  readonly network: GuildsNetwork;
  readonly addresses: {
    factory: StarknetAddress | undefined;
    guildTemplate: StarknetAddress | undefined;
    tokenTemplate: StarknetAddress | undefined;
    governorTemplate: StarknetAddress | undefined;
  };
  createGuild(params: CreateGuildParams): Promise<{ transactionHash: string }>;
  registerAddresses(addresses: WireGuildAddressesParams): WireGuildAddressesParams;
  resolveGuildAddresses(guildAddress: StarknetAddress): Promise<GuildAddresses>;
  governanceAction(params: GovernanceActionParams): Promise<{ transactionHash: string }>;
  vote(params: VoteParams): Promise<{ transactionHash: string }>;
  treasuryAction(params: TreasuryActionParams): Promise<{ transactionHash: string }>;
  buyShares(params: ShareActionParams): Promise<{ transactionHash: string }>;
  redeemShares(params: ShareActionParams): Promise<{ transactionHash: string }>;
}

export class DefaultGuildsClient implements GuildsClient {
  public readonly network: GuildsNetwork;
  public readonly addresses: {
    factory: StarknetAddress | undefined;
    guildTemplate: StarknetAddress | undefined;
    tokenTemplate: StarknetAddress | undefined;
    governorTemplate: StarknetAddress | undefined;
  };

  private readonly transport: ContractTransport;
  private readonly retry: GuildsClientOptions['retry'];
  private readonly factory: FactoryBindings;
  private readonly guild: GuildBindings;

  public constructor(transport: ContractTransport, options: GuildsClientOptions) {
    this.transport = transport;
    this.factory = createFactoryBindings(this.transport);
    this.guild = createGuildBindings(this.transport);
    this.network = options.network;
    this.retry = options.retry;

    const defaults = DEFAULT_NETWORK_ADDRESSES[options.network] ?? {};
    this.addresses = {
      factory: options.addresses?.factory ?? defaults.factory,
      guildTemplate: options.addresses?.guildTemplate ?? defaults.guildTemplate,
      tokenTemplate: options.addresses?.tokenTemplate ?? defaults.tokenTemplate,
      governorTemplate: options.addresses?.governorTemplate ?? defaults.governorTemplate,
    };
  }

  public async createGuild(params: CreateGuildParams): Promise<{ transactionHash: string }> {
    const factory = this.requireFactoryAddress();
    this.validateCreateGuildParams(params);

    return withRetry(
      'createGuild',
      async () => this.factory.createGuild(factory, params),
      this.retry,
    ).catch((error: unknown) => {
      throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
    });
  }

  public registerAddresses(addresses: WireGuildAddressesParams): WireGuildAddressesParams {
    assertAddress(addresses.guild, 'guild');
    assertAddress(addresses.token, 'token');
    assertAddress(addresses.governor, 'governor');
    return wireAddresses(addresses);
  }

  public async resolveGuildAddresses(guildAddress: StarknetAddress): Promise<GuildAddresses> {
    const factory = this.requireFactoryAddress();
    return withRetry('resolveGuildAddresses', async () => {
      const raw = await this.factory.getGuild(factory, guildAddress);
      return decodeGuildAddresses(raw);
    }, this.retry).catch((error: unknown) => {
      throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
    });
  }

  public async governanceAction(params: GovernanceActionParams): Promise<{ transactionHash: string }> {
    return withRetry('governanceAction', async () => this.guild.propose(params), this.retry).catch(
      (error: unknown) => {
        throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
      },
    );
  }

  public async vote(params: VoteParams): Promise<{ transactionHash: string }> {
    return withRetry('vote', async () => this.guild.vote(params), this.retry).catch((error: unknown) => {
      throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
    });
  }

  public async treasuryAction(params: TreasuryActionParams): Promise<{ transactionHash: string }> {
    return withRetry('treasuryAction', async () => this.guild.executeCoreAction(params), this.retry).catch(
      (error: unknown) => {
        throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
      },
    );
  }

  public async buyShares(params: ShareActionParams): Promise<{ transactionHash: string }> {
    return withRetry('buyShares', async () => this.guild.buyShares(params), this.retry).catch(
      (error: unknown) => {
        throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
      },
    );
  }

  public async redeemShares(params: ShareActionParams): Promise<{ transactionHash: string }> {
    return withRetry('redeemShares', async () => this.guild.redeemShares(params), this.retry).catch(
      (error: unknown) => {
        throw toGuildsSdkError(error, 'CONTRACT_CALL_FAILED');
      },
    );
  }

  private requireFactoryAddress(): StarknetAddress {
    const configured = this.addresses.factory;
    const fallback = DEFAULT_NETWORK_ADDRESSES[this.network]?.factory;
    const factory = configured ?? fallback;
    if (!factory) {
      throw new GuildsSdkError(
        'MISSING_ADDRESS',
        `Missing factory address for network '${this.network}'. Provide options.addresses.factory.`,
      );
    }
    return assertAddress(factory, 'factory');
  }

  private validateCreateGuildParams(params: CreateGuildParams): void {
    if (!params.name || !params.ticker) {
      throw new GuildsSdkError('INVALID_INPUT', 'name and ticker are required');
    }
    assertAddress(params.depositToken, 'depositToken');
    if (params.depositAmount < 0n || params.initialTokenSupply < 0n) {
      throw new GuildsSdkError('INVALID_INPUT', 'depositAmount and initialTokenSupply must be >= 0');
    }
  }
}
