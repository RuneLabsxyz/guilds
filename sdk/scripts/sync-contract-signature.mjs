import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sdkRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(sdkRoot, '..');

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

const sources = {};
for (const relPath of interfaceFiles) {
  const absPath = path.join(repoRoot, relPath);
  const source = await fs.readFile(absPath, 'utf8');
  sources[relPath] = {
    functions: extractFunctions(source),
  };
}

const signature = {
  version: 1,
  sources,
};

const outPath = path.join(sdkRoot, 'generated', 'contracts.signature.json');
await fs.mkdir(path.dirname(outPath), { recursive: true });
await fs.writeFile(outPath, `${JSON.stringify(signature, null, 2)}\n`, 'utf8');
console.log(`Updated ${path.relative(sdkRoot, outPath)}`);
