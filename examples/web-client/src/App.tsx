import { useMemo, useState } from 'react';
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

  const bundle = useMemo(() => createBrowserClientBundle(network, factory), [network, factory]);
  const invokes = bundle.transport.getState().invokes;

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
            <p>Form and tx submission land in slice 2.</p>
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
