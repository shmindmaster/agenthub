#!/usr/bin/env node
// Static check of a product repository against demo-harness/v1
// (kits/demo-harness/README.md). Reads the repo; never runs or changes it.
//
// Usage: node validate-demo-harness.mjs <repo> [--json]
// Exit 0 when the contract holds, 1 when it does not, 2 on usage errors.

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validate } from '../kits/schema-subset.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const asJson = args.includes('--json');
const repoArg = args.find((arg) => !arg.startsWith('--'));
if (!repoArg) {
  console.error('Usage: validate-demo-harness.mjs <repo> [--json]');
  process.exit(2);
}
const repo = resolve(repoArg);
const failures = [];
const notes = [];
const fail = (message) => failures.push(message);

const harnessPath = join(repo, 'demo', 'harness.json');
let harness;
if (!existsSync(harnessPath)) {
  fail('missing demo/harness.json');
} else {
  try {
    harness = JSON.parse(readFileSync(harnessPath, 'utf8'));
  } catch (error) {
    fail(`demo/harness.json is not JSON: ${error.message}`);
  }
}

if (harness) {
  const schema = JSON.parse(readFileSync(join(here, '..', 'kits', 'demo-harness', 'harness.schema.json'), 'utf8'));
  for (const error of validate(schema, harness)) fail(`demo/harness.json ${error}`);

  // Reset: the named command must be reachable through the repo's own scripts.
  const pkgPath = join(repo, 'package.json');
  const scripts = existsSync(pkgPath) ? JSON.parse(readFileSync(pkgPath, 'utf8')).scripts ?? {} : {};
  for (const [kind, command] of Object.entries(harness.reset ?? {})) {
    if (!command) continue;
    const match = /^(?:pnpm|npm run|yarn|bun run)\s+([\w:.-]+)/.exec(command);
    if (match && !scripts[match[1]]) fail(`reset.${kind} runs "${match[1]}", which is not a package.json script`);
  }
  if (harness.reset?.full && !scripts['demo:reset']) fail('package.json has no demo:reset script');

  // Secrets never live in the harness file.
  for (const service of harness.services ?? []) {
    for (const key of Object.keys(service.env ?? {})) {
      if (/(KEY|TOKEN|SECRET|PASSWORD|DSN|DATABASE_URL)/i.test(key)) {
        fail(`services.${service.name}.env.${key} looks like a secret; read it by name from the user environment instead`);
      }
    }
    if (service.cwd && !existsSync(join(repo, service.cwd))) fail(`services.${service.name}.cwd ${service.cwd} does not exist`);
  }
  const versionServices = new Set((harness.versionEndpoints ?? []).map((endpoint) => endpoint.service));
  if (versionServices.size === 0) fail('versionEndpoints is empty: every demo needs a deployed-SHA endpoint');

  // Truth table: three sections in order, and every "Demonstrate now" row cites evidence that exists.
  const truthPath = harness.truthTable && join(repo, harness.truthTable);
  if (!truthPath || !existsSync(truthPath)) {
    fail(`truth table ${harness.truthTable ?? '(unset)'} does not exist`);
  } else {
    const text = readFileSync(truthPath, 'utf8');
    const headings = [...text.matchAll(/^##\s+(.+?)\s*$/gm)].map((m) => m[1]);
    const expected = ['Demonstrate now', 'Build next', 'Do not claim'];
    if (JSON.stringify(headings) !== JSON.stringify(expected)) {
      fail(`truth table sections are ${JSON.stringify(headings)}, want ${JSON.stringify(expected)}`);
    }
    if (/<[A-Za-z][^>]*>/.test(text.replace(/`[^`]*`/g, ''))) fail('truth table still has <placeholder> text');
    const now = text.split(/^##\s+/m).find((section) => section.startsWith('Demonstrate now')) ?? '';
    const rows = now.split('\n').filter((line) => /^\|/.test(line) && !/^\|\s*-/.test(line)).slice(1);
    if (rows.length === 0) fail('truth table "Demonstrate now" has no rows');
    for (const row of rows) {
      const cells = row.split('|').slice(1, -1).map((cell) => cell.trim());
      const refs = [...(cells[1] ?? '').matchAll(/`([^`]+)`/g)].map((m) => m[1]);
      if (refs.length === 0) fail(`"Demonstrate now" row has no evidence: ${cells[0]}`);
      for (const ref of refs) {
        const path = ref.replace(/::.*$/, '').replace(/#.*$/, '').replace(/:\d+$/, '');
        if (/^(GET|POST|PUT|PATCH|DELETE) \//.test(path) || path.startsWith('/')) continue; // an endpoint
        if (!existsSync(join(repo, path))) fail(`"Demonstrate now" evidence ${ref} does not exist`);
      }
    }
  }

  // The synthetic label must be rendered by product source, not only declared.
  if (harness.syntheticLabel?.testId && !sourceMentions(repo, harness.syntheticLabel.testId)) {
    fail(`no product source renders data-testid="${harness.syntheticLabel.testId}"`);
  }

  // Smoke spec must exist in the repo.
  if (harness.smokeSpec && !existsSync(join(repo, harness.smokeSpec))) fail(`smokeSpec ${harness.smokeSpec} does not exist`);
  if (!harness.smokeSpec) notes.push('no smokeSpec declared');
}

function sourceMentions(root, needle) {
  const skip = new Set(['node_modules', '.git', 'dist', 'build', '.venv', 'venv', '.next', 'coverage']);
  // The harness folder and docs at the repo root declare the label; they do not render it.
  const rootOnlySkip = new Set(['demo', 'docs']);
  const stack = [root];
  let budget = 20000;
  while (stack.length > 0 && budget > 0) {
    const dir = stack.pop();
    let entries;
    try { entries = readdirSync(dir, { withFileTypes: true }); } catch { continue; }
    for (const entry of entries) {
      if (entry.isDirectory()) {
        const skipped = skip.has(entry.name) || (dir === root && rootOnlySkip.has(entry.name));
        if (!skipped && !entry.name.startsWith('.')) stack.push(join(dir, entry.name));
      } else if (/\.(tsx|jsx|ts|js|mjs|cjs|mts|vue|svelte|html|py)$/.test(entry.name) && !/\.(spec|test)\./.test(entry.name)) {
        budget -= 1;
        try { if (readFileSync(join(dir, entry.name), 'utf8').includes(needle)) return true; } catch { /* unreadable file */ }
      }
    }
  }
  return false;
}

const result = { ok: failures.length === 0, repo, failures, notes };
if (asJson) console.log(JSON.stringify(result, null, 2));
else if (result.ok) console.log(`PASS demo-harness/v1: ${repo}${notes.length ? ` (${notes.join('; ')})` : ''}`);
else console.error(`FAIL demo-harness/v1: ${repo}\n${failures.map((f) => `  - ${f}`).join('\n')}`);
process.exit(result.ok ? 0 : 1);
