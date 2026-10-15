#!/usr/bin/env node
import { randomBytes } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

if (Number(process.versions.node.split('.')[0]) < 24) {
  console.error('Anamne requires Node.js 24 or newer.');
  process.exit(1);
}

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const data = join(root, 'data');
const envPath = join(root, '.env');
mkdirSync(data, { recursive: true, mode: 0o700 });

const contents = [
  '# Anamne personal sync configuration. Keep this file private.',
  `ANAMNE_API_TOKEN=${randomBytes(32).toString('hex')}`,
  `ANAMNE_DB_PATH=${JSON.stringify(join(data, 'anamne.sqlite'))}`,
  'ANAMNE_HOST=127.0.0.1',
  'ANAMNE_PORT=8787',
  '# Exact trusted browser origins, comma-separated; empty is fine for native clients.',
  'ANAMNE_CORS_ORIGINS=',
  '',
].join('\n');

try {
  writeFileSync(envPath, contents, { flag: 'wx', mode: 0o600 });
  console.log('Created .env with a random admin token; existing configurations are never overwritten.');
} catch (error) {
  if (error.code !== 'EEXIST') throw error;
  console.log('Existing .env kept unchanged.');
}
console.log('Start from the package root: node --env-file=.env server/src/http.js');
