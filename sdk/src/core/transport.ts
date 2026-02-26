export interface CallRequest {
  contractAddress: string;
  entrypoint: string;
  calldata: readonly string[];
}

export interface InvokeRequest extends CallRequest {
  maxFee?: bigint;
}

export interface ContractTransport {
  call<T = string[]>(request: CallRequest): Promise<T>;
  invoke(request: InvokeRequest): Promise<{ transactionHash: string }>;
}
