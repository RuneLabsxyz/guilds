import { type FormEvent, useMemo, useState } from 'react';
import type { GuildsNetwork } from '@runelabsxyz/guilds-sdk';
import { createBrowserClientBundle } from './sdk/client';

const NETWORKS: GuildsNetwork[] = ['local', 'sepolia', 'mainnet'];

function isStarknetAddress(value: string): value is `0x${string}` {
  return /^0x[0-9a-fA-F]+$/.test(value);
}

export function App() {
  const [network, setNetwork] = useState<GuildsNetwork>('local');
  const [factoryInput, setFactoryInput] = useState('0xabc');
  const [refreshTick, setRefreshTick] = useState(0);

  const factory = isStarknetAddress(factoryInput) ? factoryInput : ('0xabc' as `0x${string}`);
  const [createForm, setCreateForm] = useState({
    name: 'FoundersGuild',
    ticker: 'FG',
    depositToken: '0xdef',
    depositAmount: '10',
    initialTokenSupply: '1000',
  });
  const [createResult, setCreateResult] = useState<{
    txHash: string;
    guild: string;
    token: string;
    governor: string;
  } | null>(null);
  const [createError, setCreateError] = useState<string | null>(null);

  const bundle = useMemo(() => createBrowserClientBundle(network, factory), [network, factory]);
  const invokes = bundle.transport.getState().invokes;

  async function onCreateGuildSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setCreateError(null);

    try {
      const tx = await bundle.client.createGuild({
        name: createForm.name,
        ticker: createForm.ticker,
        depositToken: createForm.depositToken as `0x${string}`,
        depositAmount: BigInt(createForm.depositAmount),
        initialTokenSupply: BigInt(createForm.initialTokenSupply),
        governorConfig: {
          votingDelay: 1n,
          votingPeriod: 20n,
          proposalThreshold: 1n,
          quorumBps: 1_000,
          timelockDelay: 1n,
        },
      });

      const addresses = await bundle.client.resolveGuildAddresses('0x111');
      setCreateResult({
        txHash: tx.transactionHash,
        guild: addresses.guild,
        token: addresses.token,
        governor: addresses.governor,
      });
    } catch (error) {
      setCreateError(error instanceof Error ? error.message : 'Create guild failed');
    }
  }

  return (
    <div className="page-shell">
      <header className="hero">
        <p className="kicker">RuneLabs Guilds</p>
        <h1>SDK Web Client Playground</h1>
        <p className="hero-copy">
          This browser app uses <code>@runelabsxyz/guilds-sdk</code> directly and exposes create guild, governance,
          and treasury workflows in one place.
        </p>
      </header>

      <section className="panel">
        <h2>Client Setup</h2>
        <div className="grid two">
          <label>
            <span>Network</span>
            <select value={network} onChange={(event) => setNetwork(event.target.value as GuildsNetwork)}>
              {NETWORKS.map((item) => (
                <option key={item} value={item}>
                  {item}
                </option>
              ))}
            </select>
          </label>

          <label>
            <span>Factory Address</span>
            <input
              value={factoryInput}
              onChange={(event) => setFactoryInput(event.target.value)}
              placeholder="0x..."
            />
          </label>
        </div>

        <div className="status-row">
          <p>
            SDK client ready for <strong>{bundle.client.network}</strong>.
          </p>
          <button type="button" onClick={() => setRefreshTick((value) => value + 1)}>
            Refresh Activity ({refreshTick})
          </button>
        </div>
      </section>

      <section className="panel muted">
        <h2>Workflows (Next Slices)</h2>
        <div className="grid three">
          <article>
            <h3>Create Guild</h3>
            <p>Create guild now available below.</p>
          </article>
          <article>
            <h3>Governance + Vote Todo</h3>
            <p>Proposal todo list and voting controls land in slice 3.</p>
          </article>
          <article>
            <h3>Treasury Actions</h3>
            <p>Send money and approval actions land in slice 4.</p>
          </article>
        </div>
      </section>

      <section className="panel">
        <h2>Create Guild</h2>
        <form className="grid three" onSubmit={onCreateGuildSubmit}>
          <label>
            <span>Name</span>
            <input
              value={createForm.name}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, name: event.target.value }))}
            />
          </label>
          <label>
            <span>Ticker</span>
            <input
              value={createForm.ticker}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, ticker: event.target.value }))}
            />
          </label>
          <label>
            <span>Deposit Token</span>
            <input
              value={createForm.depositToken}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, depositToken: event.target.value }))}
            />
          </label>
          <label>
            <span>Deposit Amount</span>
            <input
              value={createForm.depositAmount}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, depositAmount: event.target.value }))}
            />
          </label>
          <label>
            <span>Initial Token Supply</span>
            <input
              value={createForm.initialTokenSupply}
              onChange={(event) => setCreateForm((prev) => ({ ...prev, initialTokenSupply: event.target.value }))}
            />
          </label>
          <div className="actions">
            <button type="submit">Create Guild</button>
          </div>
        </form>
        {createResult ? (
          <div className="result">
            <p>
              <strong>Tx:</strong> <code>{createResult.txHash}</code>
            </p>
            <p>
              <strong>Guild:</strong> <code>{createResult.guild}</code>
            </p>
            <p>
              <strong>Token:</strong> <code>{createResult.token}</code>
            </p>
            <p>
              <strong>Governor:</strong> <code>{createResult.governor}</code>
            </p>
          </div>
        ) : null}
        {createError ? <p className="error">{createError}</p> : null}
      </section>

      <section className="panel">
        <h2>Transport Activity</h2>
        {invokes.length === 0 ? (
          <p className="empty">No SDK invoke calls yet.</p>
        ) : (
          <ul className="activity-list">
            {invokes.map((item) => (
              <li key={`${item.transactionHash}-${item.createdAtIso}`}>
                <div>
                  <strong>{item.entrypoint}</strong>
                  <p>{item.contractAddress}</p>
                </div>
                <code>{item.transactionHash}</code>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
