// Re-verify a code-stage receipt against the repository: every file sha256 and blob, every shown line, every
// highlight band. Also checks, when given, the played-<shot>.json files that the browser wrote after hashing the
// lines it actually rendered. Exit 0 = the film shows exactly this code; 1 = something differs.
// Usage: node verify-receipt.mjs <jobRoot>/capture/code-stage/receipt.json [--repo <path>]
import fs from 'node:fs';
import path from 'node:path';
import { verifyCodeReceipt } from './source.mjs';

const argv = process.argv.slice(2);
const file = argv.find((a) => !a.startsWith('--'));
if (!file) { console.error('usage: node verify-receipt.mjs <receipt.json> [--repo <path>]'); process.exit(2); }
const i = argv.indexOf('--repo');
const receipt = JSON.parse(fs.readFileSync(file, 'utf8'));
const res = verifyCodeReceipt(receipt, i >= 0 ? argv[i + 1] : receipt.repo);
const dir = path.dirname(path.resolve(file));
const rendered = [];
for (const s of receipt.shots.filter((x) => x.kind === 'code')) {
  const p = path.join(dir, `played-${s.id}.json`);
  if (!fs.existsSync(p)) { rendered.push({ id: s.id, checked: false }); continue; }
  const v = JSON.parse(fs.readFileSync(p, 'utf8')).verification || [];
  const ok = v.length > 0 && v.every((r) => r.ok);
  if (!ok) res.problems.push(`${s.id}: rendered lines did not hash to the receipt`);
  rendered.push({ id: s.id, checked: true, ok });
}
const ok = res.problems.length === 0;
console.log(JSON.stringify({ ok, files: receipt.files.length, shots: receipt.shots.length, rendered, problems: res.problems }, null, 2));
process.exit(ok ? 0 : 1);
