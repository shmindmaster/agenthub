#!/usr/bin/env node
// Word-onset gate only, not the proposed 2.1 render/receipt/pixel gate. Whisper is never its clock.
import { existsSync, readFileSync, mkdirSync, writeFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const library = [join(here, 'sync-lib.mjs'), join(here, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
const { measureWordSync } = await import(pathToFileURL(library).href);
const [rootArg, candidateArg] = process.argv.slice(2);
if (!rootArg || !candidateArg) { console.error('usage: validate-word-sync.mjs <jobRoot> <candidate>'); process.exit(2); }
const root = resolve(rootArg), candidate = resolve(candidateArg);
const digest = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const json = (p) => JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
const cue = join(root, 'plan', 'cue-sheet.json'), alignment = join(root, 'qa', 'encoded-alignment.json');
let result, sha256, bytes, inputs;
try {
  sha256 = digest(candidate); bytes = statSync(candidate).size;
  const scriptSha256 = digest(join(root, 'story', 'locked-script.txt'));
  inputs = { cueSheet: { path: 'plan/cue-sheet.json', sha256: digest(cue) }, alignment: { path: 'qa/encoded-alignment.json', sha256: digest(alignment) }, script: { path: 'story/locked-script.txt', sha256: scriptSha256 } };
  const words = json(cue).beats.flatMap((b) => b.narration?.words || []);
  result = measureWordSync(json(alignment), words, { takeSha256: sha256, scriptSha256 });
  if (digest(candidate) !== sha256) throw new Error('candidate changed during word-sync QA');
} catch (e) { result = { ok: false, errors: [e.message] }; }
const report = { generator: 'media-studio/validate-word-sync', ...result, candidate: { path: candidate, sha256, bytes }, inputs, thresholds: { driftMaxMs: 40 }, limitations: ['80 ms aligner grid is not 40 ms acoustic accuracy', 'alignment constrains text, independent transcript/listen review required', 'rendered word/diagram pixel timing is not measured by this patch'] };
const out = join(root, 'qa', 'word-sync.json');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ ok: report.ok, errors: report.errors, offsetMs: report.offsetMs, driftMs: report.driftMs, out }));
process.exit(report.ok ? 0 : 1);
