// Record the screen beats of one media-studio product-screencast job and finish each take with Recast.
// This is the only path that produces the picture of a `screen` beat (product-picture.md); PNG stills are
// diagnostic. Runs from the external job workspace; the product repository is read-only.
//
// Usage: node record-job.mjs <jobRoot> [S05 S06 ...] [--no-recast] [--headed]
// Reads  <jobRoot>/capture/scenes.mjs:
//   export const order = ['S05', ...];                      // default recording order
//   export const options = { baseUrl, storageState?, viewport?, deviceScaleFactor?, recast?: { S05: { autoZoom: false } } };
//   export const scenes = { async S05(h, ctx) {...} };      // one function per screen beat; h = record-lib helpers
//   ctx = { page, beats, id, jobRoot, targetSeconds }       // targetSeconds = narration length of the beat, or null
// Writes <jobRoot>/capture/clips/<id>.webm                  (Recast: cursor approach, click ripple, punch-in zoom)
//        <jobRoot>/capture/beats/<id>.json                  (beat marks with elapsed seconds and bounding boxes)
//        <jobRoot>/capture/recordings.json                  (take length vs narration target, Recast status, errors)
//        <jobRoot>/capture/receipt.json                     (hash-bound capture receipt; validate-product-picture reads it)
// One Recast render at a time (it writes .recast-tmp inside the clips dir). A Recast failure retries without
// autoZoom, then falls back to the raw WebM with recast: "fallback" recorded; the validator decides whether
// a fallback is acceptable (only when job.json says recastFallbackAllowed with a reason). Nothing is silent.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { startRecording, finishRecording, renderRecast } from './record-lib.mjs';

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('--')));
const [jobRootArg, ...only] = argv.filter((a) => !a.startsWith('--'));
if (!jobRootArg) { console.error('usage: node record-job.mjs <jobRoot> [S05 ...] [--no-recast] [--headed]'); process.exit(2); }
const jobRoot = path.resolve(jobRootArg);
const job = JSON.parse(fs.readFileSync(path.join(jobRoot, 'job.json'), 'utf8').replace(/^﻿/, ''));
if (job.repositoryWritePolicy !== 'read-only') throw new Error('job.json must record repositoryWritePolicy: read-only before capture');
const cap = path.join(jobRoot, 'capture');
fs.mkdirSync(path.join(cap, 'clips'), { recursive: true });
fs.mkdirSync(path.join(cap, 'beats'), { recursive: true });
process.chdir(cap);

const mod = await import(pathToFileURL(path.join(cap, 'scenes.mjs')).href);
const scenes = mod.scenes || {};
const order = mod.order || Object.keys(scenes);
const options = mod.options || {};
if (!options.baseUrl) throw new Error('capture/scenes.mjs must export options.baseUrl');
const storageState = options.storageState ? path.resolve(cap, options.storageState) : null;
if (storageState && !fs.existsSync(storageState)) throw new Error('storageState not found: ' + storageState);

// Narration length per scene so a take can be paced to the words.
const targets = {};
const tlPath = path.join(jobRoot, 'story', 'narration-timeline.json');
if (fs.existsSync(tlPath)) {
  const tl = JSON.parse(fs.readFileSync(tlPath, 'utf8').replace(/^﻿/, ''));
  for (const s of tl.segments || []) { const sc = s.scene || String(s.id).replace(/[a-z]$/, ''); targets[sc] = (targets[sc] || 0) + Number(s.durationSeconds || 0); }
}

const sha256 = (f) => createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const probe = (f) => { try { return parseFloat(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString()); } catch { return 0; } };
const here = path.dirname(fileURLToPath(import.meta.url));
let recastVersion = null;
try { recastVersion = JSON.parse(fs.readFileSync(path.join(here, 'node_modules', 'playwright-recast', 'package.json'), 'utf8')).version; } catch { /* resolved below */ }
if (!recastVersion) { try { const p = fileURLToPath(await import.meta.resolve('playwright-recast/package.json')); recastVersion = JSON.parse(fs.readFileSync(p, 'utf8')).version; } catch { recastVersion = null; } }
let playwrightVersion = null;
try { playwrightVersion = JSON.parse(fs.readFileSync(fileURLToPath(await import.meta.resolve('playwright/package.json')), 'utf8')).version; } catch { playwrightVersion = null; }

const recPath = path.join(cap, 'recordings.json');
const recordings = fs.existsSync(recPath) ? JSON.parse(fs.readFileSync(recPath, 'utf8')) : { jobRoot: path.basename(jobRoot), takes: {} };
const receiptPath = path.join(cap, 'receipt.json');
const receipt = fs.existsSync(receiptPath) ? JSON.parse(fs.readFileSync(receiptPath, 'utf8')) : { schemaVersion: '1.0.0', generator: 'media-studio/record-job', clips: {} };
receipt.generator = 'media-studio/record-job';
receipt.playwrightVersion = playwrightVersion;
receipt.recastVersion = recastVersion;
receipt.baseUrl = options.baseUrl;
const save = () => { fs.writeFileSync(recPath, JSON.stringify(recordings, null, 2)); fs.writeFileSync(receiptPath, JSON.stringify(receipt, null, 2)); };

const ids = only.length ? only : order;
for (const id of ids) {
  if (!scenes[id]) { console.log('no scene function for', id); recordings.takes[id] = { error: 'no scene function' }; save(); continue; }
  console.log('=== recording', id, targets[id] ? `(narration ${targets[id].toFixed(1)} s)` : '');
  fs.rmSync(path.resolve('clips', '.recast-tmp'), { recursive: true, force: true });
  const rec = await startRecording(id, {
    storageState, baseUrl: options.baseUrl, viewport: options.viewport, deviceScaleFactor: options.deviceScaleFactor,
    headless: !flags.has('--headed'), colorScheme: options.colorScheme, timezoneId: options.timezoneId, extraHTTPHeaders: options.extraHTTPHeaders,
  });
  const t0 = Date.now();
  const take = { startedAt: new Date(t0).toISOString(), targetSeconds: targets[id] ? Number(targets[id].toFixed(1)) : null };
  try { await scenes[id](rec.h, { page: rec.page, beats: rec.beats, id, jobRoot, targetSeconds: targets[id] || null }); }
  catch (e) { take.error = e.message.split('\n')[0]; console.log('  scene error:', take.error); await rec.page.screenshot({ path: path.join(rec.rawDir, 'error.png') }).catch(() => {}); }
  const fin = await finishRecording(rec);
  take.rawSeconds = Number(((Date.now() - t0) / 1000).toFixed(1));
  fs.writeFileSync(path.join(cap, 'beats', `${id}.json`), JSON.stringify({ id, marks: fin.beats, expectations: fin.expectations }, null, 2));
  const out = path.resolve('clips', `${id}.webm`);
  const opts = (options.recast || {})[id] || {};
  if (flags.has('--no-recast')) { fs.copyFileSync(fin.webm, out); take.recast = 'skipped'; }
  else {
    try { await renderRecast(fin.rawDir, out, { ...opts, resolution: options.viewport }); take.recast = opts.autoZoom === false ? 'noZoom' : 'full'; }
    catch (e) {
      console.log('  recast failed:', e.message.split('\n')[0]);
      fs.rmSync(path.resolve('clips', '.recast-tmp'), { recursive: true, force: true });
      try { await renderRecast(fin.rawDir, out, { ...opts, autoZoom: false, resolution: options.viewport }); take.recast = 'noZoom'; take.recastNote = e.message.split('\n')[0]; }
      catch (e2) { fs.copyFileSync(fin.webm, out); take.recast = 'fallback'; take.recastNote = e2.message.split('\n')[0]; console.log('  raw webm copied (recast fallback)'); }
    }
  }
  for (const ext of ['png', 'jpg']) { const p = path.resolve('clips', `${id}.${ext}`); if (fs.existsSync(p)) fs.unlinkSync(p); }
  take.clipSeconds = Number(probe(out).toFixed(1));
  take.ratio = take.targetSeconds ? Number((take.clipSeconds / take.targetSeconds).toFixed(2)) : null;
  take.short = take.ratio !== null && take.ratio < 0.85;
  take.events = fin.summary;
  const valid = !take.error && fin.summary.pointerMoves > 0 && fin.summary.expectationsFailed.length === 0;
  take.valid = valid;
  recordings.takes[id] = take;
  receipt.clips[id] = {
    file: `clips/${id}.webm`,
    sha256: sha256(out),
    bytes: fs.statSync(out).size,
    clipSeconds: take.clipSeconds,
    rawWebmSha256: sha256(fin.webm),
    traceSha256: fs.existsSync(fin.tracePath) ? sha256(fin.tracePath) : null,
    recordedAt: take.startedAt,
    viewport: rec.viewport,
    deviceScaleFactor: options.deviceScaleFactor || 2,
    recast: take.recast,
    recastNote: take.recastNote || null,
    events: fin.summary,
    expectations: fin.expectations,
    beats: fin.beats,
    error: take.error || null,
    valid,
  };
  save();
  console.log(`  clip ${take.clipSeconds}s${take.targetSeconds ? ` for ${take.targetSeconds}s of narration (${take.ratio}x)` : ''} recast=${take.recast} moves=${fin.summary.pointerMoves} clicks=${fin.summary.clicks} expectations=${fin.summary.expectationsObserved}/${fin.summary.expectations}${valid ? '' : '  INVALID: ' + (take.error || fin.summary.expectationsFailed.join(',') || 'no pointer motion')}${take.short ? '  SHORT: pace the take to the narration or split the beat' : ''}`);
}
console.log('done', ids.join(' '));
