#!/usr/bin/env node
// Sidecar captions from aligner words. Fast speech stays one cue and is marked rate-bound.
// Usage: node write-captions.mjs <jobRoot> [--words story/narration-words.json] [--out qa/captions.srt]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { captionCues, cuesToSrt, normalizeAlignWords } from './picture-gates.mjs';

const argv = process.argv.slice(2);
const flag = (name, fallback) => { const index = argv.indexOf(name); return index >= 0 ? argv[index + 1] : fallback; };
const jobRoot = argv.find((arg, index) => !arg.startsWith('--') && !(index > 0 && argv[index - 1].startsWith('--')));
if (!jobRoot) { console.error('Usage: node write-captions.mjs <jobRoot> [--words story/narration-words.json] [--out qa/captions.srt]'); process.exit(1); }
const root = resolve(jobRoot);
const wordsPath = resolve(root, flag('--words', 'story/narration-words.json'));
const raw = JSON.parse(readFileSync(wordsPath, 'utf8').replace(/^\uFEFF/, ''));
const { cues, rateBound } = captionCues(normalizeAlignWords(raw).words.map((word) => ({ word: word.w, start: word.start, end: word.end })));
const out = resolve(root, flag('--out', 'qa/captions.srt'));
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, cuesToSrt(cues));
const texts = {};
for (const cue of cues) if (cue.rateBound) texts[String(cue.index)] = cue.text;
const report = resolve(root, 'qa', 'caption-rate-bound.json');
mkdirSync(dirname(report), { recursive: true });
writeFileSync(report, `${JSON.stringify({ generator: 'media-studio/write-captions', cues: rateBound, texts, reason: 'speech is faster than 20 characters a second and the next word starts immediately' }, null, 2)}\n`);
console.log(JSON.stringify({ ok: true, cues: cues.length, rateBound }));
