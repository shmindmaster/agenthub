#!/usr/bin/env node
// Snapshot the numbers in the approved narration. A later fluff rewrite has to keep this multiset.
// Usage: node lock-facts.mjs <jobRoot> [--from story/locked-script.txt]
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { factNumbers } from './picture-gates.mjs';

const argv = process.argv.slice(2);
const fromFlag = argv.indexOf('--from');
const from = fromFlag >= 0 ? argv[fromFlag + 1] : 'story/locked-script.txt';
const jobRoot = argv.find((arg, index) => !arg.startsWith('--') && !(index > 0 && argv[index - 1].startsWith('--')));
if (!jobRoot) { console.error('Usage: node lock-facts.mjs <jobRoot> [--from story/locked-script.txt]'); process.exit(1); }
const root = resolve(jobRoot);
const sourcePath = resolve(root, from);
const text = readFileSync(sourcePath, 'utf8');
const numbers = factNumbers(text);
const out = join(root, 'story', 'fact-lock.json');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify({
  generator: 'media-studio/lock-facts',
  source: from.replace(/\\/g, '/'),
  sha256: createHash('sha256').update(text).digest('hex'),
  numbers,
}, null, 2)}\n`);
console.log(JSON.stringify({ ok: true, numbers: numbers.length, out: 'story/fact-lock.json' }));
