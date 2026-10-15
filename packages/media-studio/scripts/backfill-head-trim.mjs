#!/usr/bin/env node
// Record the Recast head trim on capture receipts written before record-job.mjs measured it.
//
// Recast trims the blank lead-in off the head of every render (playwright-recast render/renderer.js detectBlankLeadIn,
// up to 3 s), while record-lib logs actions, marks and expectations on the raw recording clock. Without the trim the
// sync tooling would place every event late by that amount, so build-cue-sheet.mjs refuses such clips. This measures
// the trim the way Recast does, on the raw WebM the receipt points at, and writes it beside the clip:
//   clips[id].recastHeadTrimSeconds, recastHeadTrimMethod ("... (backfilled)"), rawMinusClipSeconds
// The raw WebM must still be under capture/raw/<id>/ and hash to clips[id].rawWebmSha256; otherwise the clip is left
// alone and listed (re-record it). Entries that already carry a trim are not touched.
//
// Usage: node backfill-head-trim.mjs <jobRoot> [--recast-dir <node_modules/playwright-recast>] [--dry-run]
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const jobRoot = path.resolve(argv.find((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1].startsWith('--'))) || '');
const receiptPath = path.join(jobRoot, 'capture', 'receipt.json');
if (!fs.existsSync(receiptPath)) { console.error('usage: node backfill-head-trim.mjs <jobRoot>  (needs capture/receipt.json)'); process.exit(2); }
const dryRun = argv.includes('--dry-run');
const here = path.dirname(fileURLToPath(import.meta.url));
const recastDir = [flag('--recast-dir'), path.join(here, '..', 'kit', 'node_modules', 'playwright-recast'), path.join(here, '..', 'node_modules', 'playwright-recast'),
  path.join(here, 'node_modules', 'playwright-recast')].filter(Boolean).find((d) => fs.existsSync(path.join(d, 'dist', 'render', 'renderer.js')));
if (!recastDir) { console.error('playwright-recast not found; pass --recast-dir <path to node_modules/playwright-recast>'); process.exit(2); }
const { detectBlankLeadIn } = await import(pathToFileURL(path.join(recastDir, 'dist', 'render', 'renderer.js')).href);
const recastVersion = JSON.parse(fs.readFileSync(path.join(recastDir, 'package.json'), 'utf8')).version;

const sha256 = (f) => createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const probe = (f) => { try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString()) || 0; } catch { return 0; } };
const receipt = JSON.parse(fs.readFileSync(receiptPath, 'utf8').replace(/^﻿/, ''));
const done = [], skipped = [], refused = [];
for (const [id, clip] of Object.entries(receipt.clips || {})) {
  if (Number.isFinite(clip.recastHeadTrimSeconds) || clip.actionClock === 'clip') { skipped.push({ id, why: 'already has a head trim' }); continue; }
  if (clip.recast === 'skipped' || clip.recast === 'fallback') { skipped.push({ id, why: `raw copy (${clip.recast}); clipClock uses 0` }); continue; }
  const rawDir = path.join(jobRoot, 'capture', 'raw', id);
  const raw = fs.existsSync(rawDir) ? fs.readdirSync(rawDir).filter((f) => f.endsWith('.webm')).map((f) => path.join(rawDir, f)) : [];
  const match = raw.find((f) => !clip.rawWebmSha256 || sha256(f) === clip.rawWebmSha256);
  const clipFile = path.join(jobRoot, 'capture', clip.file || `clips/${id}.webm`);
  if (!match) { refused.push({ id, why: raw.length ? 'raw WebM does not match rawWebmSha256' : 'no raw WebM under capture/raw' }); continue; }
  if (!fs.existsSync(clipFile) || (clip.sha256 && sha256(clipFile) !== clip.sha256)) { refused.push({ id, why: 'clip file missing or not the receipt-bound clip' }); continue; }
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'head-trim-'));
  let detected;
  try { detected = Number(detectBlankLeadIn(match, tmp).toFixed(3)); } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
  const lengthDelta = Number(Math.max(0, probe(match) - probe(clipFile)).toFixed(3));
  const entry = { recastHeadTrimSeconds: detected, recastHeadTrimMethod: `playwright-recast ${recastVersion} detectBlankLeadIn on the raw WebM (backfilled)`, rawMinusClipSeconds: lengthDelta };
  if (!dryRun) Object.assign(clip, entry);
  done.push({ id, ...entry, agreesWithLength: Math.abs(detected - lengthDelta) <= 0.15 });
}
if (!dryRun && done.length) fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ ok: refused.length === 0, dryRun, receipt: receiptPath, backfilled: done, skipped, refused }, null, 2));
process.exit(refused.length ? 1 : 0);
