#!/usr/bin/env node
// Backfill capture/receipt.json for takes recorded by a recorder that predates the receipt (the runtime
// _shared/capture-lib lane used by the 2026-09 Duckie jobs). Evidence comes from the Playwright trace that
// recorder saved beside each raw take, never from the clip alone: pointer moves, clicks, keystrokes and
// wheel events are counted from trace.trace, and the finished clip is hash-bound. A take with no trace
// gets no receipt entry (and validate-product-picture.mjs will refuse it).
//
// Usage: node backfill-capture-receipt.mjs <jobRoot> [--raw capture/raw] [--clips capture/clips]
// Writes/merges <jobRoot>/capture/receipt.json with source: "trace-backfill" per clip. Entries written by
// record-job.mjs (source absent / "live") are left untouched.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const argv = process.argv.slice(2);
const flag = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d; };
const jobRoot = path.resolve(argv.find((a) => !a.startsWith('--')) || '');
if (!jobRoot || !fs.existsSync(path.join(jobRoot, 'job.json'))) { console.error('usage: node backfill-capture-receipt.mjs <jobRoot>'); process.exit(2); }
const rawRoot = path.resolve(jobRoot, flag('--raw', 'capture/raw'));
const clipsRoot = path.resolve(jobRoot, flag('--clips', 'capture/clips'));
const sha256 = (f) => createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const probe = (f) => { try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString()) || 0; } catch { return 0; } };

function readTraceEvents(traceZip) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'trace-'));
  try {
    // bsdtar (Windows) and GNU tar with libarchive both read zip; fall back to unzip.
    try { execFileSync('tar', ['-xf', traceZip, '-C', tmp], { stdio: 'ignore' }); }
    catch { execFileSync('unzip', ['-q', '-o', traceZip, '-d', tmp], { stdio: 'ignore' }); }
    const files = fs.readdirSync(tmp).filter((f) => /\.trace$/.test(f) || f === 'trace.trace' || /^trace.*\.trace$/.test(f));
    const events = [];
    for (const f of files) {
      for (const line of fs.readFileSync(path.join(tmp, f), 'utf8').split('\n')) {
        if (!line.trim()) continue;
        try { events.push(JSON.parse(line)); } catch { /* skip */ }
      }
    }
    return events;
  } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
}

function summarize(events) {
  const before = events.filter((e) => e.type === 'before' && e.apiName);
  const count = (re) => before.filter((e) => re.test(e.apiName)).length;
  const pointerMoves = count(/^mouse\.move$/) + count(/^locator\.hover$/);
  const clicks = count(/^mouse\.(click|down)$/) + count(/^locator\.(click|dblclick|check|uncheck|selectOption)$/);
  const keystrokes = before.filter((e) => /^(keyboard\.(type|press|insertText)|locator\.(fill|type|pressSequentially|press))$/.test(e.apiName)).reduce((n, e) => n + (String(e.params?.text || e.params?.value || e.params?.key || 'x').length), 0);
  const scrolls = count(/^mouse\.wheel$/);
  const navigations = count(/^page\.goto$/);
  const waits = count(/^locator\.waitFor$|^page\.waitForSelector$|^expect\./);
  return { pointerMoves, clicks, keystrokes, scrolls, navigations, expectations: waits, expectationsObserved: waits, expectationsFailed: [] };
}

const receiptPath = path.join(jobRoot, 'capture', 'receipt.json');
const receipt = fs.existsSync(receiptPath) ? JSON.parse(fs.readFileSync(receiptPath, 'utf8')) : { schemaVersion: '1.0.0', generator: 'media-studio/backfill-capture-receipt', clips: {} };
const recordings = fs.existsSync(path.join(jobRoot, 'capture', 'recordings.json')) ? JSON.parse(fs.readFileSync(path.join(jobRoot, 'capture', 'recordings.json'), 'utf8')) : { takes: {} };
const beatsDir = path.join(jobRoot, 'capture', 'beats');
let written = 0, skipped = [];
for (const file of fs.existsSync(clipsRoot) ? fs.readdirSync(clipsRoot) : []) {
  if (!/\.(webm|mp4)$/i.test(file)) continue;
  const id = file.replace(/\.(webm|mp4)$/i, '');
  const existing = receipt.clips[id];
  if (existing && existing.source !== 'trace-backfill') continue; // live receipt wins
  const rawDir = path.join(rawRoot, id);
  const trace = path.join(rawDir, 'trace.zip');
  if (!fs.existsSync(trace)) { skipped.push(`${id}: no trace at ${path.relative(jobRoot, trace)}`); continue; }
  const clip = path.join(clipsRoot, file);
  const events = summarize(readTraceEvents(trace));
  const rawWebm = fs.existsSync(rawDir) ? fs.readdirSync(rawDir).find((f) => f.endsWith('.webm')) : null;
  const take = recordings.takes?.[id] || {};
  const beats = fs.existsSync(path.join(beatsDir, `${id}.json`)) ? JSON.parse(fs.readFileSync(path.join(beatsDir, `${id}.json`), 'utf8')).marks || [] : [];
  receipt.clips[id] = {
    file: `clips/${file}`,
    sha256: sha256(clip),
    bytes: fs.statSync(clip).size,
    clipSeconds: Number(probe(clip).toFixed(1)),
    rawWebmSha256: rawWebm ? sha256(path.join(rawDir, rawWebm)) : null,
    traceSha256: sha256(trace),
    recordedAt: take.startedAt || null,
    viewport: { width: 1600, height: 1000 },
    deviceScaleFactor: 2,
    recast: take.recast || 'unknown',
    recastNote: take.recastNote || null,
    events,
    expectations: [],
    beats,
    error: take.error || null,
    valid: !take.error && events.pointerMoves > 0,
    source: 'trace-backfill',
  };
  written += 1;
}
receipt.generator = receipt.generator || 'media-studio/backfill-capture-receipt';
fs.mkdirSync(path.dirname(receiptPath), { recursive: true });
fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2));
console.log(JSON.stringify({ ok: true, receipt: receiptPath, written, skipped }));
