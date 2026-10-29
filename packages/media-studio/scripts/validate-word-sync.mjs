#!/usr/bin/env node
// Word-onset gate only, not the proposed 2.1 render/receipt/pixel gate. Whisper is never its clock.
import { existsSync, readFileSync, mkdirSync, writeFileSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const library = [join(here, 'sync-lib.mjs'), join(here, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
const { measureWordSync } = await import(pathToFileURL(library).href);
const { readVerifiedMap, measureMappedClock } = await import('./edit-map-clock.mjs');
const { readHostedClock, measureHostedClock } = await import('./hosted-alignment-clock.mjs');
const { readDerivedAudioClock, measureDerivedAudioClock } = await import('./derived-audio-clock.mjs');
const { readQueueQwenClock, measureQueueQwenClock } = await import('./queue-qwen-alignment-clock.mjs');
const [rootArg, candidateArg] = process.argv.slice(2);
if (!rootArg || !candidateArg) { console.error('usage: validate-word-sync.mjs <jobRoot> <candidate>'); process.exit(2); }
const root = resolve(rootArg), candidate = resolve(candidateArg);
const digest = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const json = (p) => JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
const cue = join(root, 'plan', 'cue-sheet.json'), nativeAlignment = join(root, 'qa', 'encoded-alignment.json');
// Explicit graph selects the separate verification route; never an automatic fallback.
const hostedAlignment=join(root,'qa','hosted-encoded-alignment.json');
const derivedAlignment=join(root,'qa','derived-audio-clock.json');
const queueAlignment=join(root,'qa','queue-qwen-alignment.json');
const alignment = existsSync(queueAlignment) ? queueAlignment : existsSync(derivedAlignment) ? derivedAlignment : existsSync(hostedAlignment) ? hostedAlignment : existsSync(join(root,'plan','edit-map.json')) ? join(root,'qa','encoded-edit-map.json') : nativeAlignment;
let result, sha256, bytes, inputs;
try {
  sha256 = digest(candidate); bytes = statSync(candidate).size;
  const scriptSha256 = digest(join(root, 'story', 'locked-script.txt'));
  inputs = { cueSheet: { path: 'plan/cue-sheet.json', sha256: digest(cue) }, alignment: { path: alignment === queueAlignment ? 'qa/queue-qwen-alignment.json' : alignment === derivedAlignment ? 'qa/derived-audio-clock.json' : alignment === hostedAlignment ? 'qa/hosted-encoded-alignment.json' : alignment === nativeAlignment ? 'qa/encoded-alignment.json' : 'qa/encoded-edit-map.json', sha256: digest(alignment) }, script: { path: 'story/locked-script.txt', sha256: scriptSha256 } };
  const words = json(cue).beats.flatMap((b) => b.narration?.words || []);
  const jobPath = join(root, 'job.json');
  const allowAsrAnchored = existsSync(jobPath) && json(jobPath)?.clockPolicy?.allowAsrAnchored === true;
  const isEditMap=alignment!==nativeAlignment && alignment!==hostedAlignment && alignment!==derivedAlignment && alignment!==queueAlignment;
  const bindings = { takeSha256: sha256, scriptSha256, allowAsrAnchored,...(isEditMap ? {editMapSha256:digest(join(root,'plan','edit-map.json'))} : {}) };
  result = alignment === queueAlignment ? measureQueueQwenClock(readQueueQwenClock(root,json(alignment),bindings),words)
    : alignment === derivedAlignment ? measureDerivedAudioClock(readDerivedAudioClock(root,json(alignment),bindings),words)
    : alignment === hostedAlignment ? measureHostedClock(readHostedClock(root,json(alignment),bindings),words)
    : alignment === nativeAlignment ? measureWordSync(json(alignment), words, bindings)
    : measureMappedClock(readVerifiedMap(root, json(alignment), bindings), words);
  if (isEditMap) inputs.editMap = { path:'plan/edit-map.json', sha256:digest(join(root,'plan','edit-map.json')) };
  if (digest(candidate) !== sha256) throw new Error('candidate changed during word-sync QA');
} catch (e) { result = { ok: false, errors: [e.message] }; }
const report = { generator: 'media-studio/validate-word-sync', ...result, candidate: { path: candidate, sha256, bytes }, inputs, thresholds: { driftMaxMs: 40 }, limitations: [...(result.limitations||[]), '80 ms aligner grid is not 40 ms acoustic accuracy', 'verified edit maps preserve source uncertainty; they are not a new forced alignment', 'alignment constrains text, independent transcript/listen review required', 'rendered word/diagram pixel timing is not measured by this patch'] };
const out = join(root, 'qa', 'word-sync.json');
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ ok: report.ok, errors: report.errors, offsetMs: report.offsetMs, driftMs: report.driftMs, out }));
process.exit(report.ok ? 0 : 1);
