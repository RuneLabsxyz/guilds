import { type FormEvent, useMemo, useState } from 'react';
import type { GuildsNetwork } from '@runelabsxyz/guilds-sdk';
import { createBrowserClientBundle } from './sdk/client';

const NETWORKS: GuildsNetwork[] = ['local', 'sepolia', 'mainnet'];

interface ProposalTodo {
  id: number;
  proposalId: bigint;
  title: string;
  description: string;
  forVotes: number;
  againstVotes: number;
  abstainVotes: number;
  lastTxHash: string;
}

interface TreasuryActivity {
  id: number;
  mode: 'transfer' | 'approve';
  target: string;
  token: string;
  amount: string;
  txHash: string;
}

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
  const [governorAddress, setGovernorAddress] = useState('0x333');
  const [proposalForm, setProposalForm] = useState({ title: 'Fund toolchain grant', description: 'Approve monthly ops budget.' });
  const [proposalTodos, setProposalTodos] = useState<ProposalTodo[]>([]);
  const [governanceError, setGovernanceError] = useState<string | null>(null);
  const [treasuryForm, setTreasuryForm] = useState({
    guild: '0x111',
    target: '0x777',
    token: '0x222',
    amount: '50',
    mode: 'transfer' as 'transfer' | 'approve',
  });
  const [treasuryActivities, setTreasuryActivities] = useState<TreasuryActivity[]>([]);
  const [treasuryError, setTreasuryError] = useState<string | null>(null);

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
      setGovernorAddress(addresses.governor);
      setTreasuryForm((prev) => ({ ...prev, guild: addresses.guild, token: addresses.token }));
    } catch (error) {
      setCreateError(error instanceof Error ? error.message : 'Create guild failed');
    }
  }

  async function onSubmitProposal(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setGovernanceError(null);

    try {
      const tx = await bundle.client.governanceAction({
        governor: governorAddress as `0x${string}`,
        targets: ['0x111'],
        values: [0n],
        calldatas: ['0x0'],
        description: `${proposalForm.title}: ${proposalForm.description}`,
      });

      setProposalTodos((prev) => {
        const id = prev.length + 1;
        return [
          {
            id,
            proposalId: BigInt(id),
            title: proposalForm.title,
            description: proposalForm.description,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            lastTxHash: tx.transactionHash,
          },
          ...prev,
        ];
      });
      setProposalForm({ title: '', description: '' });
    } catch (error) {
      setGovernanceError(error instanceof Error ? error.message : 'Submit proposal failed');
    }
  }

  async function onVote(todoId: number, support: 0 | 1 | 2) {
    setGovernanceError(null);
    const proposal = proposalTodos.find((item) => item.id === todoId);
    if (!proposal) {
      return;
    }

    try {
      const tx = await bundle.client.vote({
        governor: governorAddress as `0x${string}`,
        proposalId: proposal.proposalId,
        support,
      });

      setProposalTodos((prev) =>
        prev.map((item) => {
          if (item.id !== todoId) {
            return item;
          }

          return {
            ...item,
            forVotes: support === 1 ? item.forVotes + 1 : item.forVotes,
            againstVotes: support === 0 ? item.againstVotes + 1 : item.againstVotes,
            abstainVotes: support === 2 ? item.abstainVotes + 1 : item.abstainVotes,
            lastTxHash: tx.transactionHash,
          };
        }),
      );
    } catch (error) {
      setGovernanceError(error instanceof Error ? error.message : 'Vote failed');
    }
  }

  async function onTreasurySubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setTreasuryError(null);

    try {
      const actionType = treasuryForm.mode === 'transfer' ? 1 : 2;
      const tx = await bundle.client.treasuryAction({
        guild: treasuryForm.guild as `0x${string}`,
        actionType,
        target: treasuryForm.target as `0x${string}`,
        token: treasuryForm.token as `0x${string}`,
        amount: BigInt(treasuryForm.amount),
        calldata: [],
      });

      setTreasuryActivities((prev) => [
        {
          id: prev.length + 1,
          mode: treasuryForm.mode,
          target: treasuryForm.target,
          token: treasuryForm.token,
          amount: treasuryForm.amount,
          txHash: tx.transactionHash,
        },
        ...prev,
      ]);
    } catch (error) {
      setTreasuryError(error instanceof Error ? error.message : 'Treasury action failed');
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
            <p>Proposal todo list and vote buttons now available below.</p>
          </article>
          <article>
            <h3>Treasury Actions</h3>
            <p>Send money and approve spender actions now available below.</p>
          </article>
        </div>
      </section>

      <section className="panel">
        <h2>Governance Todo List</h2>
        <form className="grid three" onSubmit={onSubmitProposal}>
          <label>
            <span>Governor Address</span>
            <input value={governorAddress} onChange={(event) => setGovernorAddress(event.target.value)} />
          </label>
          <label>
            <span>Proposal Title</span>
            <input
              value={proposalForm.title}
              onChange={(event) => setProposalForm((prev) => ({ ...prev, title: event.target.value }))}
            />
          </label>
          <label>
            <span>Proposal Description</span>
            <input
              value={proposalForm.description}
              onChange={(event) => setProposalForm((prev) => ({ ...prev, description: event.target.value }))}
            />
          </label>
          <div className="actions">
            <button type="submit">Submit Proposal</button>
          </div>
        </form>

        {proposalTodos.length === 0 ? (
          <p className="empty">No proposal todos yet.</p>
        ) : (
          <ul className="todo-list">
            {proposalTodos.map((item) => (
              <li key={item.id}>
                <div>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                  <p>
                    Votes: <strong>For {item.forVotes}</strong> / Against {item.againstVotes} / Abstain {item.abstainVotes}
                  </p>
                  <code>{item.lastTxHash}</code>
                </div>
                <div className="vote-actions">
                  <button type="button" onClick={() => onVote(item.id, 1)}>
                    Vote For
                  </button>
                  <button type="button" onClick={() => onVote(item.id, 0)}>
                    Vote Against
                  </button>
                  <button type="button" onClick={() => onVote(item.id, 2)}>
                    Abstain
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
        {governanceError ? <p className="error">{governanceError}</p> : null}
      </section>

      <section className="panel">
        <h2>Treasury: Send Money / Approve</h2>
        <form className="grid three" onSubmit={onTreasurySubmit}>
          <label>
            <span>Guild Address</span>
            <input
              value={treasuryForm.guild}
              onChange={(event) => setTreasuryForm((prev) => ({ ...prev, guild: event.target.value }))}
            />
          </label>
          <label>
            <span>Action</span>
            <select
              value={treasuryForm.mode}
              onChange={(event) =>
                setTreasuryForm((prev) => ({ ...prev, mode: event.target.value as 'transfer' | 'approve' }))
              }
            >
              <option value="transfer">Send Money (transfer)</option>
              <option value="approve">Get Approval (approve)</option>
            </select>
          </label>
          <label>
            <span>Target</span>
            <input
              value={treasuryForm.target}
              onChange={(event) => setTreasuryForm((prev) => ({ ...prev, target: event.target.value }))}
            />
          </label>
          <label>
            <span>Token</span>
            <input
              value={treasuryForm.token}
              onChange={(event) => setTreasuryForm((prev) => ({ ...prev, token: event.target.value }))}
            />
          </label>
          <label>
            <span>Amount</span>
            <input
              value={treasuryForm.amount}
              onChange={(event) => setTreasuryForm((prev) => ({ ...prev, amount: event.target.value }))}
            />
          </label>
          <div className="actions">
            <button type="submit">Run Treasury Action</button>
          </div>
        </form>

        {treasuryActivities.length === 0 ? (
          <p className="empty">No treasury actions submitted yet.</p>
        ) : (
          <ul className="treasury-list">
            {treasuryActivities.map((item) => (
              <li key={item.id}>
                <div>
                  <h3>{item.mode === 'transfer' ? 'Transfer' : 'Approve'}</h3>
                  <p>
                    Target: <code>{item.target}</code>
                  </p>
                  <p>
                    Token: <code>{item.token}</code>
                  </p>
                  <p>Amount: {item.amount}</p>
                </div>
                <code>{item.txHash}</code>
              </li>
            ))}
          </ul>
        )}
        {treasuryError ? <p className="error">{treasuryError}</p> : null}
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
