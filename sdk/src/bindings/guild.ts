import type { ContractTransport } from '../core/transport.js';
import type {
  GovernanceActionParams,
  ShareActionParams,
  StarknetAddress,
  TreasuryActionParams,
  VoteParams,
  WireGuildAddressesParams,
} from '../types/contracts.js';

export interface GuildBindings {
  setGovernorAddress(guild: StarknetAddress, governor: StarknetAddress): Promise<{ transactionHash: string }>;
  executeCoreAction(params: TreasuryActionParams): Promise<{ transactionHash: string }>;
  buyShares(params: ShareActionParams): Promise<{ transactionHash: string }>;
  redeemShares(params: ShareActionParams): Promise<{ transactionHash: string }>;
  getGovernorAddress(guild: StarknetAddress): Promise<StarknetAddress>;
  getTokenAddress(guild: StarknetAddress): Promise<StarknetAddress>;
  propose(params: GovernanceActionParams): Promise<{ transactionHash: string }>;
  vote(params: VoteParams): Promise<{ transactionHash: string }>;
}

export function createGuildBindings(transport: ContractTransport): GuildBindings {
  return {
    async setGovernorAddress(guild, governor): Promise<{ transactionHash: string }> {
      return transport.invoke({
        contractAddress: guild,
        entrypoint: 'set_governor_address',
        calldata: [governor],
      });
    },

    async executeCoreAction(params): Promise<{ transactionHash: string }> {
      const calldata = [
        `0x${params.actionType.toString(16)}`,
        params.target,
        params.token,
        `0x${params.amount.toString(16)}`,
        `0x${params.calldata.length.toString(16)}`,
        ...params.calldata,
      ];
      return transport.invoke({
        contractAddress: params.guild,
        entrypoint: 'execute_core_action',
        calldata,
      });
    },

    async buyShares(params): Promise<{ transactionHash: string }> {
      return transport.invoke({
        contractAddress: params.guild,
        entrypoint: 'buy_shares',
        calldata: [`0x${params.amount.toString(16)}`],
      });
    },

    async redeemShares(params): Promise<{ transactionHash: string }> {
      return transport.invoke({
        contractAddress: params.guild,
        entrypoint: 'redeem_shares',
        calldata: [`0x${params.amount.toString(16)}`],
      });
    },

    async getGovernorAddress(guild): Promise<StarknetAddress> {
      const raw = await transport.call<string[]>({
        contractAddress: guild,
        entrypoint: 'get_governor_address',
        calldata: [],
      });
      return raw[0] as StarknetAddress;
    },

    async getTokenAddress(guild): Promise<StarknetAddress> {
      const raw = await transport.call<string[]>({
        contractAddress: guild,
        entrypoint: 'get_token_address',
        calldata: [],
      });
      return raw[0] as StarknetAddress;
    },

    async propose(params): Promise<{ transactionHash: string }> {
      const calldata = [
        `0x${params.targets.length.toString(16)}`,
        ...params.targets,
        `0x${params.values.length.toString(16)}`,
        ...params.values.map((v) => `0x${v.toString(16)}`),
        `0x${params.calldatas.length.toString(16)}`,
        ...params.calldatas,
        params.description,
      ];
      return transport.invoke({
        contractAddress: params.governor,
        entrypoint: 'propose',
        calldata,
      });
    },

    async vote(params): Promise<{ transactionHash: string }> {
      return transport.invoke({
        contractAddress: params.governor,
        entrypoint: 'cast_vote',
        calldata: [`0x${params.proposalId.toString(16)}`, `0x${params.support.toString(16)}`],
      });
    },
  };
}

export function wireAddresses(input: WireGuildAddressesParams): WireGuildAddressesParams {
  return input;
}
