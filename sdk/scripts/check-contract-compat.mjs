import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sdkRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(sdkRoot, '..');

const snapshotPath = path.join(sdkRoot, 'generated', 'contracts.signature.json');

const interfaceFiles = [
  'src/interfaces/factory.cairo',
  'src/interfaces/guild.cairo',
  'src/interfaces/token.cairo',
];

function extractFunctions(contents) {
  const regex = /\bfn\s+([a-zA-Z0-9_]+)\s*\(/g;
  const names = [];
  let match;
  while ((match = regex.exec(contents)) !== null) {
    names.push(match[1]);
  }
  return Array.from(new Set(names));
}

function compareArrays(expected, actual) {
  const expectedSet = new Set(expected);
  const actualSet = new Set(actual);
  const missing = expected.filter((name) => !actualSet.has(name));
  const added = actual.filter((name) => !expectedSet.has(name));
  return { missing, added };
}

const snapshotRaw = await fs.readFile(snapshotPath, 'utf8');
const snapshot = JSON.parse(snapshotRaw);

const issues = [];

for (const relPath of interfaceFiles) {
  const absPath = path.join(repoRoot, relPath);
  const source = await fs.readFile(absPath, 'utf8');
  const currentFns = extractFunctions(source);
  const expectedFns = snapshot.sources?.[relPath]?.functions ?? [];
  const diff = compareArrays(expectedFns, currentFns);

  if (diff.missing.length > 0 || diff.added.length > 0) {
    issues.push({
      path: relPath,
      missing: diff.missing,
      added: diff.added,
    });
  }
}

if (issues.length > 0) {
  console.error('SDK contract compatibility check failed. Snapshot is out of sync.');
  for (const issue of issues) {
    console.error(`- ${issue.path}`);
    if (issue.added.length > 0) {
      console.error(`  added: ${issue.added.join(', ')}`);
    }
    if (issue.missing.length > 0) {
      console.error(`  removed: ${issue.missing.join(', ')}`);
    }
  }
  console.error('Run: npm run sync:contracts');
  process.exit(1);
}

console.log('SDK compatibility check passed: contract interfaces match snapshot.');
