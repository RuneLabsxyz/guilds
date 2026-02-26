import type { CallRequest, ContractTransport, InvokeRequest } from '../../src/core/transport.js';

export class MockTransport implements ContractTransport {
  public readonly calls: CallRequest[] = [];
  public readonly invokes: InvokeRequest[] = [];
  private callResponse: string[] = [];

  public setCallResponse(response: string[]): void {
    this.callResponse = response;
  }

  public async call<T = string[]>(request: CallRequest): Promise<T> {
    this.calls.push(request);
    return this.callResponse as T;
  }

  public async invoke(request: InvokeRequest): Promise<{ transactionHash: string }> {
    this.invokes.push(request);
    return { transactionHash: '0xabc123' };
  }
}
