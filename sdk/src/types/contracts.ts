export type StarknetAddress = `0x${string}`;

export type BigNumberish = bigint | number | string;

export interface GovernorConfig {
  votingDelay: bigint;
  votingPeriod: bigint;
  proposalThreshold: bigint;
  quorumBps: number;
  timelockDelay: bigint;
}

export interface CreateGuildParams {
  name: string;
  ticker: string;
  depositToken: StarknetAddress;
  depositAmount: bigint;
  initialTokenSupply: bigint;
  governorConfig: GovernorConfig;
}

export interface GuildAddresses {
  guild: StarknetAddress;
  token: StarknetAddress;
  governor: StarknetAddress;
}

export interface WireGuildAddressesParams {
  guild: StarknetAddress;
  token: StarknetAddress;
  governor: StarknetAddress;
}

export interface GovernanceActionParams {
  governor: StarknetAddress;
  targets: StarknetAddress[];
  values: bigint[];
  calldatas: string[];
  description: string;
}

export interface VoteParams {
  governor: StarknetAddress;
  proposalId: bigint;
  support: 0 | 1 | 2;
}

export interface TreasuryActionParams {
  guild: StarknetAddress;
  actionType: number;
  target: StarknetAddress;
  token: StarknetAddress;
  amount: bigint;
  calldata: string[];
}

export interface ShareActionParams {
  guild: StarknetAddress;
  amount: bigint;
}
