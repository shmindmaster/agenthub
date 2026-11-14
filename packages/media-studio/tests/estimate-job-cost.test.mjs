import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
const here = dirname(fileURLToPath(import.meta.url));
const run = (...a) => JSON.parse(execFileSync(process.execPath, [join(here, '../scripts/estimate-job-cost.mjs'), ...a, '--json'], { encoding: 'utf8' }));
test('tiers rise in cost and Azure narration is not priced as USD', () => {
  const r = run('--scenes', '9', '--words', '120', '--stills', '6', '--hero', '2');
  const [d, s, p] = r.tiers.map((t) => t.usd);
  assert.ok(d > 0 && d < s && s < p, `draft ${d} < standard ${s} < premium ${p}`);
  assert.equal(r.tiers[0].rows.find((x) => x[0].startsWith('narration'))[2], null);
});
test('Batch halves the OpenAI image and text estimate', () => {
  const a = run('--scenes', '9', '--stills', '6', '--tier', 'standard').tiers[0];
  const b = run('--scenes', '9', '--stills', '6', '--tier', 'standard', '--batch').tiers[0];
  const img = (t) => t.rows.find((x) => x[0].includes('stills'))[2];
  assert.ok(Math.abs(img(b) - img(a) / 2) < 1e-9);
});
test('OpenAI voice is priced and refuses a missing scene count', () => {
  const r = run('--scenes', '4', '--words', '150', '--voice', 'openai', '--tier', 'draft');
  assert.ok(r.tiers[0].rows.find((x) => x[0].startsWith('narration'))[2] > 0);
  assert.throws(() => execFileSync(process.execPath, [join(here, '../scripts/estimate-job-cost.mjs')], { stdio: 'pipe' }));
});