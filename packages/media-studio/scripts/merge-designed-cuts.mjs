#!/usr/bin/env node
// Put card mounts and spotlight ramps back on the cue sheet after an aligner overwrites it.
// Usage: node merge-designed-cuts.mjs <jobRoot> [--offset 0]
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { designedCuts, pictureScripts } from './picture-gates.mjs';

const argv = process.argv.slice(2);
const offsetFlag = argv.indexOf('--offset');
const offset = offsetFlag >= 0 ? Number(argv[offsetFlag + 1]) : 0;
const jobRoot = argv.find((arg, index) => !arg.startsWith('--') && !(index > 0 && argv[index - 1].startsWith('--')));
if (!jobRoot) { console.error('Usage: node merge-designed-cuts.mjs <jobRoot> [--offset <seconds>]'); process.exit(1); }
const root = resolve(jobRoot);
const scripts = pictureScripts(root).flat();
const timing = {};
for (const line of scripts) {
  const path = join(root, 'voice', 'align', `${line.id}.json`);
  if (!existsSync(path)) continue;
  const report = JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
  timing[line.id] = { s: Number(report.lineStart ?? 0) + offset, words: (report.words || []).map((word) => ({ ...word, s: Number(word.s ?? word.start) + offset })) };
}
const designed = designedCuts(scripts, timing, 0);
if (designed.misses.length) {
  for (const miss of designed.misses) console.error(`[designed-cuts] ${miss}`);
  process.exit(1);
}
const cuePath = join(root, 'plan', 'cue-sheet.json');
const cue = existsSync(cuePath) ? JSON.parse(readFileSync(cuePath, 'utf8').replace(/^\uFEFF/, '')) : { beats: [] };
const existing = Array.isArray(cue.edl) ? cue.edl : [];
const have = new Set(existing.map((cut) => cut.startSeconds));
cue.edl = [...existing, ...designed.cuts.filter((start) => !have.has(start)).map((startSeconds) => ({ startSeconds, kind: 'designed' }))].sort((a, b) => a.startSeconds - b.startSeconds);
writeFileSync(cuePath, `${JSON.stringify(cue, null, 2)}\n`);
console.log(JSON.stringify({ ok: true, cuts: cue.edl.length }));
