#!/usr/bin/env node
// Narration-to-visual sync gate on the EXACT encoded candidate. Directive: VIDEO-SYNC-DIRECTIVE §4.
// Usage: node validate-sync.mjs <jobRoot> <candidate.mp4> [--cue-sheet plan/cue-sheet.json] [--asr qa/encoded-asr.json]
//                               [--out qa/sync.json] [--allow-degraded]
//        thresholds: --action-tolerance-ms 300 --screen-tolerance-ms 40 --result-hold 1.5 --drift-ms 40
//                    --scene-threshold 0.4 --max-freeze 4 --max-hold 6.5 --max-dropped 3
//
// The cue sheet (build-cue-sheet.mjs, "mapped" mode, built after compose) says where every spoken word, screen change,
// click and result is meant to be on the program timeline. This gate holds the encoded file to it:
//   screen-on       the beat's screen is up by its first content word      EDL + scene cut detected in the encoded picture
//   action-timing   the click / typing / pointer arrival lands within +-300 ms of its spoken verb or object   receipt action time through the EDL
//   result-hold     the resulting UI state stays up >= 1.5 s after the line names it (and after it appears)
//   narration-order the line never names a result before the picture shows it, or after the screen is gone
//   av-sync         encoded audio vs cue-sheet words, <= 40 ms drift: qa/encoded-alignment.json from ai.ps1 align.
//                   The raw 80 ms grid is reported, not represented as 40 ms acoustic accuracy. Whisper is text only.
//                   Legacy jobs without a forced-clock contract retain diagnostic speech-onset detection (120 ms).
//   dropped-frames  pts gaps in the video packets
//   frozen-frames   a freeze is a stalled picture while the cue sheet expects change; a hold the cue sheet declares is not a freeze
//                   stalled         an exact-frame freeze (any length, freezedetect reports >= 2 s) covering +-0.25 s of a screen cut,
//                                   an unproved/state-changing action_time, result's visible_at or an edl clip start fails.
//                                   Hash-bound receipt target/motion proof can establish a pointer-only read beat; recorder-measured
//                                   prior visibility and target box can establish an existing-state observation. Neither promises a pixel transition.
//                                   where the sheet says it does
//                   declared hold   from max(last action_time, result.visible_at) to the beat's slot_end (a beat with no action and no
//                                   result, such as a card, holds from its slot_start). A freeze wholly inside it passes as a
//                                   'declared-hold' finding with the hold length, up to --max-hold (default 6.5 s); longer fails
//                   anything else   an exact-frame freeze > --max-freeze (4 s) outside every declared hold fails
//                   The result-hold check (>= 1.5 s on screen after the result) is unchanged. Capture scripts never need a scroll
//                   jiggle to pass: hold still on the result and let the cue sheet say so.
//   text-clipping   OCR on sampled frames, advisory; only when tesseract is installed
// Writes qa/sync.json bound to the candidate SHA-256 and byte count with per-beat findings and the explicit list of checks NOT performed.
// Viewer release (validate-viewer-release.mjs) requires a PASS report for this exact file.
import { existsSync, readFileSync, writeFileSync, mkdirSync, statSync, mkdtempSync, rmSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import os from 'node:os';
import { dirname, join, resolve, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { readPhysicalResultObservations, applyPhysicalResultObservations } from './physical-result-observations.mjs';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const libPath = [join(scriptDir, 'sync-lib.mjs'), join(scriptDir, '..', 'kit', 'screencast', 'sync-lib.mjs')].find(existsSync);
if (!libPath) { console.error('sync-lib.mjs not found beside this script or in ../kit/screencast'); process.exit(2); }
const L = await import(pathToFileURL(libPath).href);
const {readDerivedAudioClock,measureDerivedAudioClock}=await import('./derived-audio-clock.mjs');

const argv = process.argv.slice(2);
const VALUE_FLAGS = new Set(['--cue-sheet', '--asr', '--out', '--action-tolerance-ms', '--screen-tolerance-ms', '--result-hold', '--drift-ms', '--scene-threshold', '--max-freeze', '--max-hold', '--max-dropped']);
const pos = []; const opt = {};
for (let i = 0; i < argv.length; i++) { if (VALUE_FLAGS.has(argv[i])) opt[argv[i]] = argv[++i]; else if (argv[i].startsWith('--')) opt[argv[i]] = true; else pos.push(argv[i]); }
const [jobRoot, candidateArg] = pos;
if (!jobRoot || !candidateArg) { console.error('Usage: node validate-sync.mjs <jobRoot> <candidate.mp4> [--cue-sheet <file>] [--asr <file>] [--out qa/sync.json] [--allow-degraded]'); process.exit(1); }
const root = resolve(jobRoot);
const candidate = resolve(candidateArg);
const num = (n, d) => (opt[n] !== undefined ? Number(opt[n]) : d);
const T = {
  actionToleranceMs: num('--action-tolerance-ms', L.SYNC_DEFAULTS.actionToleranceMs),
  screenToleranceMs: num('--screen-tolerance-ms', L.SYNC_DEFAULTS.screenToleranceMs),
  resultHoldMinSeconds: num('--result-hold', L.SYNC_DEFAULTS.resultHoldMinSeconds),
  driftMaxMs: num('--drift-ms', L.SYNC_DEFAULTS.driftMaxMs),
  onsetOffsetMaxMs: L.SYNC_DEFAULTS.onsetOffsetMaxMs,
  sceneThreshold: num('--scene-threshold', L.SYNC_DEFAULTS.sceneThreshold),
  maxFreezeSeconds: num('--max-freeze', L.SYNC_DEFAULTS.maxFreezeSeconds),
  maxHoldSeconds: num('--max-hold', L.SYNC_DEFAULTS.maxHoldSeconds),
  maxDroppedFrames: num('--max-dropped', L.SYNC_DEFAULTS.maxDroppedFrames),
};
const allowDegraded = !!opt['--allow-degraded'];
const outPath = resolve(root, typeof opt['--out'] === 'string' ? opt['--out'] : 'qa/sync.json');
const cuePath = resolve(root, typeof opt['--cue-sheet'] === 'string' ? opt['--cue-sheet'] : 'plan/cue-sheet.json');
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');

const errors = []; const warnings = []; const performed = new Set(); const notPerformed = []; const beatRecs = new Map();
const skip = (check, reason) => { if (!notPerformed.some((n) => n.check === check)) notPerformed.push({ check, reason }); };
const rec = (beat) => { if (!beatRecs.has(beat)) beatRecs.set(beat, { beat, status: 'pass', findings: [] }); return beatRecs.get(beat); };
function finding(beat, check, status, message, expected = null, measured = null) {
  const r = rec(beat); r.findings.push({ check, status, expected, measured, message });
  if (status === 'fail') { r.status = 'fail'; errors.push(`beat ${beat}: ${check}: ${message}`); }
  else if (status === 'warn') { if (r.status === 'pass') r.status = 'warn'; warnings.push(`beat ${beat}: ${check}: ${message}`); }
}
const fail = (m) => errors.push(m);

// ---- tools
const run = (cmd, args, o = {}) => spawnSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 28, windowsHide: true, ...o });
function ffmpegAsync(args) {
  return new Promise((resolveRun) => {
    const child = spawn('ffmpeg', ['-hide_banner', '-nostats', '-threads', '2', ...args], { windowsHide: true });
    try { os.setPriority(child.pid, os.constants.priority.PRIORITY_BELOW_NORMAL); } catch { /* best effort on a loaded machine */ }
    let err = ''; child.stderr.on('data', (d) => { err += d; }); child.on('close', (code) => resolveRun({ code, stderr: err })); child.on('error', (e) => resolveRun({ code: -1, stderr: String(e) }));
  });
}

// ---- candidate
let candidateSha = null; let candidateBytes = null;
if (!existsSync(candidate)) fail(`candidate does not exist: ${candidate}`);
else { candidateSha = sha(candidate); candidateBytes = statSync(candidate).size; }

let cueSheet = null; let probe = null; let avReport = null; let freezeReport = null; let captureReceipt = null;
if (!existsSync(cuePath)) fail(`missing ${relative(root, cuePath).replace(/\\/g, '/')}: build it with build-cue-sheet.mjs (locked narration -> ASR -> compose -> build-cue-sheet).`);
else { try { cueSheet = JSON.parse(readFileSync(cuePath, 'utf8').replace(/^﻿/, '')); } catch (e) { fail(`cannot read cue sheet: ${e.message}`); } }

if (candidateSha && cueSheet) {
  if (cueSheet.generator !== 'media-studio/build-cue-sheet' || !Array.isArray(cueSheet.beats) || !cueSheet.beats.length) fail('cue sheet is not a build-cue-sheet.mjs output with beats.');
  if (cueSheet.mode !== 'mapped') fail('cue sheet is in plan mode: compose first, then rerun build-cue-sheet.mjs so action times come through the real edit decision list.');
  const tlPath = join(root, 'story', 'narration-timeline.json');
  if (existsSync(tlPath) && cueSheet.inputs?.timeline?.sha256 !== sha(tlPath)) fail('cue sheet is stale: story/narration-timeline.json changed since it was built.');
  if (cueSheet.inputs?.composeMap?.path) { const cm = join(root, cueSheet.inputs.composeMap.path); if (!existsSync(cm) || sha(cm) !== cueSheet.inputs.composeMap.sha256) fail('cue sheet is stale: the compose map changed since it was built; rerun build-cue-sheet.mjs after the last compose.'); }
  const receiptRef = cueSheet.inputs?.receipt;
  const receiptPath = join(root, 'capture', 'receipt.json');
  if (receiptRef || existsSync(receiptPath)) {
    if (receiptRef?.path !== 'capture/receipt.json' || !existsSync(receiptPath) || sha(receiptPath) !== receiptRef.sha256) fail('cue sheet is stale: capture receipt missing or changed; rebuild from the current capture receipt.');
    else {
      try { captureReceipt = JSON.parse(readFileSync(receiptPath, 'utf8').replace(/^\uFEFF/, '')); }
      catch { fail('cannot read hash-bound capture receipt.'); }
      for (const b of cueSheet.beats || []) {
        const evidenceUsed = (b.actions || []).some((a) => L.receiptSemantics(b, a, captureReceipt)) || L.receiptSemantics(b, b.result, captureReceipt, true);
        if (!evidenceUsed) continue;
        const clip = captureReceipt.clips[b.screen.clip];
        // record-job writes clip.file relative to capture/receipt.json, not the job root.
        // Do not search alternate locations: only the receipt's named artifact can prove semantics.
        const clipPath = typeof clip.file === 'string' ? resolve(dirname(receiptPath), clip.file) : null;
        if (!clipPath || !existsSync(clipPath) || sha(clipPath) !== clip.sha256) { fail(`capture evidence clip ${b.screen.clip} is missing or changed.`); captureReceipt = null; break; }
      }
    }
  }
  const pr = run('ffprobe', ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', candidate]);
  try { probe = JSON.parse(pr.stdout); } catch { fail('ffprobe cannot read the candidate.'); }
}

const beats = cueSheet?.beats || [];
let video = null; let audio = null; let duration = null; let W = 0; let H = 0; let fps = 30;
if (probe) {
  video = probe.streams.find((s) => s.codec_type === 'video'); audio = probe.streams.find((s) => s.codec_type === 'audio');
  duration = Number(probe.format.duration); W = video?.width || 0; H = video?.height || 0;
  const [n, d] = String(video?.avg_frame_rate || video?.r_frame_rate || '30/1').split('/').map(Number); fps = d ? n / d : 30;
  try {
    const ref = cueSheet.inputs?.physicalResults;
    if (ref) {
      const path = resolve(root, ref.path);
      if (!existsSync(path) || sha(path) !== ref.sha256) throw new Error('physical result observations missing or stale');
      const proof = readPhysicalResultObservations({ root, path, candidatePath: candidate, inputs: cueSheet.inputs, beats, probe });
      applyPhysicalResultObservations(beats, proof, { verify: true });
      performed.add('physical-result-observations');
    } else applyPhysicalResultObservations(beats, null, { verify: true });
  } catch (e) { fail(e.message); }
  if (!video) fail('candidate has no video stream.');
  if (Math.abs(duration - cueSheet.durationSeconds) > 1) fail(`candidate is ${duration.toFixed(2)}s but the cue sheet timeline is ${Number(cueSheet.durationSeconds).toFixed(2)}s.`);
}

// ---- precision of the narration timing
const degraded = beats.filter((b) => b.narration?.precision !== 'word');
if (degraded.length) {
  const kinds = [...new Set(degraded.map((b) => b.narration?.precision))].join('/');
  const listed = degraded.map((b) => b.beat).join(', ');
  const jobPath = join(root, 'job.json');
  let syncClock = null;
  if (existsSync(jobPath)) { try { syncClock = JSON.parse(readFileSync(jobPath, 'utf8')).syncClock; } catch { syncClock = null; } }
  const msg = syncClock === 'forced-aligner'
    ? `narration timing is ${kinds} (not word-level) on ${degraded.length} beat(s): ${listed}. word times must come from ai.ps1 align (voice/align/<id>.json, method forced-alignment). Whisper is a transcript check and cannot time the picture.`
    : `narration timing is ${kinds} (not word-level) on ${degraded.length} beat(s): ${listed}. Run word-level ASR per line (ai.ps1 transcribe <take.wav> --engine whisper --json-out voice\\asr\\<id>.json) and rebuild the cue sheet.`;
  if (allowDegraded) warnings.push(`DEGRADED: ${msg}`); else fail(msg);
}

if (candidateSha && cueSheet && probe && video) {
  // ---- one decode pass for scene cuts and exact freezes (downscaled, BelowNormal)
  const scan = await ffmpegAsync(['-i', candidate, '-an', '-vf', `scale=320:-2,freezedetect=n=0.001:d=2,select='gt(scene,${T.sceneThreshold})',showinfo`, '-f', 'null', '-']);
  if (scan.code !== 0) fail(`encoded-picture scan failed: ${scan.stderr.split(/\r?\n/).slice(-3).join(' ').trim()}`);
  const cuts = L.parseSceneCuts(scan.stderr).filter((t) => t > 0.05);
  const freezes = L.parseFreezes(scan.stderr, duration);

  // ---- dropped frames from packet pts
  const pk = run('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries', 'packet=pts_time', '-of', 'csv=p=0', candidate]);
  const pts = pk.stdout.split(/\r?\n/).map((x) => Number(x.split(',')[0])).filter(Number.isFinite);
  const drop = L.droppedFrames(pts, fps);
  performed.add('dropped-frames');
  if (drop.dropped > T.maxDroppedFrames) fail(`${drop.dropped} dropped frames (max ${T.maxDroppedFrames}); gaps at ${drop.gaps.slice(0, 5).map((g) => `${g.at}s(-${g.missing})`).join(', ')}.`);

  // ---- frozen frames: a freeze is a stalled picture where the cue sheet expects change, not a hold the sheet declares
  performed.add('frozen-frames');
  const freezeVerdicts = []; freezeReport = freezeVerdicts;
  const fmt = (f) => `${f.start.toFixed(2)}-${f.end.toFixed(2)}s`;
  const where = (beat, check, status, msg, expected, measured) => { if (beat) finding(beat, check, status, msg, expected, measured); else if (status === 'fail') fail(msg); };
  for (const f of freezes) {
    const v = L.classifyFreeze(f, { beats, edl: cueSheet.edl, receipt: captureReceipt, maxFreezeSeconds: T.maxFreezeSeconds, maxHoldSeconds: T.maxHoldSeconds });
    freezeVerdicts.push({ start: f.start, end: f.end, duration: f.duration, verdict: v.verdict, hold: v.hold });
    const b = beats.find((x) => f.start < x.slot_end && f.end > x.slot_start);
    if (v.verdict === 'stalled') {
      for (const p of v.stalled) where(p.beat ?? b?.beat, 'frozen-frames', 'fail', `the picture is stalled where the cue sheet expects ${p.what} at ${p.t.toFixed(2)}s (exact-frame freeze ${fmt(f)}, ${f.duration.toFixed(1)}s). Either the picture really changes there, or the cue sheet is wrong.`, 'picture changes at the expected time', `frozen ${fmt(f)}`);
    } else if (v.verdict === 'declared-hold') {
      where(v.hold.beat, 'declared-hold', 'pass', `exact-frame freeze ${fmt(f)} (${f.duration.toFixed(1)}s) is a declared hold: the picture is meant to stay still from ${v.hold.from.toFixed(2)}s to ${v.hold.until.toFixed(2)}s (${(v.hold.until - v.hold.from).toFixed(1)}s, ${v.hold.kind}).`, `<= ${T.maxHoldSeconds}s`, `${f.duration.toFixed(1)}s`);
    } else if (v.verdict === 'overlong-hold') {
      where(v.hold.beat, 'frozen-frames', 'fail', `exact-frame freeze ${fmt(f)} (${f.duration.toFixed(1)}s > ${T.maxFreezeSeconds}s) is inside a declared hold but longer than the ${T.maxHoldSeconds}s max hold. A static scene needs a moving cursor or guided highlight, not a held frame.`, `<= ${T.maxHoldSeconds}s`, `${f.duration.toFixed(1)}s`);
    } else if (v.verdict === 'undeclared') {
      where(b?.beat, 'frozen-frames', 'fail', `exact-frame freeze ${fmt(f)} (${f.duration.toFixed(1)}s > ${T.maxFreezeSeconds}s) outside any declared hold. A static scene needs a moving cursor or guided highlight, not a held frame.`, `<= ${T.maxFreezeSeconds}s`, `${f.duration.toFixed(1)}s`);
    }
  }

  // ---- per-beat narration/picture checks
  let narratedActions = 0;
  performed.add('screen-on'); performed.add('action-timing'); performed.add('result-hold'); performed.add('narration-order');
  const edlDeltas = [];
  for (const b of beats) {
    const words = b.narration?.words || [];
    rec(b.beat);
    if (beats.indexOf(b) > 0 && b.screen.changes_from_previous && b.screen.kind !== 'hold') {
      const wide = cuts.filter((t) => Math.abs(t - b.screen.visible_from) <= 1.0).sort((x, y) => Math.abs(x - b.screen.visible_from) - Math.abs(y - b.screen.visible_from))[0];
      if (wide !== undefined) edlDeltas.push({ beat: b.beat, delta: wide - b.screen.visible_from });
    }
    if (!words.length) { finding(b.beat, 'screen-on', 'warn', 'beat has no narration words; not checked.'); continue; }
    const fcw = b.narration.firstContentWord || { start: words[0].start };
    // screen visible by the first content word
    const idx = beats.indexOf(b);
    let screenOn = b.screen.visible_from; let method = 'edl';
    if (idx > 0 && b.screen.changes_from_previous) {
      const near = cuts.filter((t) => Math.abs(t - b.screen.visible_from) <= 0.5).sort((x, y) => Math.abs(x - b.screen.visible_from) - Math.abs(y - b.screen.visible_from))[0];
      if (near !== undefined) {
        method = 'edl+scene-cut';
        if (Math.abs(near - b.screen.visible_from) > 0.1) finding(b.beat, 'screen-on', 'fail', `the encoded picture cuts at ${near.toFixed(2)}s but the edit decision list says ${b.screen.visible_from.toFixed(2)}s; the cue sheet no longer describes this file.`, b.screen.visible_from, near);
        screenOn = Math.max(near, b.screen.visible_from);
      } else if (b.screen.kind !== 'hold') finding(b.beat, 'screen-on', 'warn', `no scene cut detected near ${b.screen.visible_from.toFixed(2)}s; screen-on time rests on the edit decision list alone (the two screens may look alike).`);
    } else if (idx === 0) screenOn = 0;
    const lateMs = (screenOn - fcw.start) * 1000;
    if (lateMs > T.screenToleranceMs) finding(b.beat, 'screen-on', 'fail', `screen appears ${lateMs.toFixed(0)} ms after the first content word "${fcw.w ?? ''}" (${fcw.start.toFixed(2)}s).`, `<= ${T.screenToleranceMs} ms late`, `${lateMs.toFixed(0)} ms late`);
    else finding(b.beat, 'screen-on', 'pass', `screen up ${(-lateMs).toFixed(0)} ms before the first content word (${method}).`, `<= ${T.screenToleranceMs} ms late`, `${lateMs.toFixed(0)} ms`);

    // actions
    const acts = (b.actions || []).filter((a) => a.narrated);
    narratedActions += acts.length;
    for (const a of acts) {
      const name = `${a.kind} "${a.label || a.target}"`;
      if (!a.keyword) { finding(b.beat, 'action-timing', 'fail', `${name} has no matching spoken word (keywords: ${(a.keywords || []).join(', ') || 'none'}). Name the action in the line, add cue-plan keywords, or mark it narrated:false.`); continue; }
      if (!Number.isFinite(a.action_time)) { finding(b.beat, 'action-timing', 'fail', `${name} has no program time; the clip edit could not be mapped (fit/extras clips are unmappable). Rebuild the cue sheet after compose.`); continue; }
      const dMs = (a.action_time - a.keyword.start) * 1000;
      if (Math.abs(dMs) > T.actionToleranceMs) finding(b.beat, 'action-timing', 'fail', `${name} lands ${Math.abs(dMs).toFixed(0)} ms ${dMs < 0 ? 'before' : 'after'} the spoken "${a.keyword.w}" (${a.keyword.start.toFixed(2)}s); allowed +-${T.actionToleranceMs} ms.`, `+-${T.actionToleranceMs} ms`, `${dMs.toFixed(0)} ms`);
      else finding(b.beat, 'action-timing', 'pass', `${name} lands ${dMs.toFixed(0)} ms from the spoken "${a.keyword.w}".`, `+-${T.actionToleranceMs} ms`, `${dMs.toFixed(0)} ms`);
      if (a.keyword.start > b.screen.visible_until) finding(b.beat, 'narration-order', 'fail', `the line names "${a.keyword.w}" after its screen is gone (${b.screen.visible_until.toFixed(2)}s).`);
    }
    // result hold and order
    if (acts.length || b.result) {
      const lastAct = acts.filter((a) => Number.isFinite(a.action_time)).map((a) => a.action_time).at(-1);
      const visible = b.result?.visible_at;
      const named = b.result?.keyword?.start;
      if (b.result && !Number.isFinite(visible)) finding(b.beat, 'result-hold', 'fail', `result "${b.result.label}" has no program time; rebuild the cue sheet after compose.`);
      else {
        if (!b.result) finding(b.beat, 'result-hold', 'warn', 'no resulting UI state declared (no h.expect in the capture, no cue-plan result); the hold is measured from the action.');
        const start = Math.max(Number.isFinite(visible) ? visible : (lastAct ?? b.slot_start), Number.isFinite(named) ? named : -Infinity);
        const hold = b.screen.visible_until - start;
        if (hold + 1e-6 < T.resultHoldMinSeconds) finding(b.beat, 'result-hold', 'fail', `result stays on screen ${hold.toFixed(2)}s after it is shown and named (${start.toFixed(2)}s -> ${b.screen.visible_until.toFixed(2)}s); needs >= ${T.resultHoldMinSeconds}s.`, `>= ${T.resultHoldMinSeconds}s`, `${hold.toFixed(2)}s`);
        else finding(b.beat, 'result-hold', 'pass', `result held ${hold.toFixed(2)}s.`, `>= ${T.resultHoldMinSeconds}s`, `${hold.toFixed(2)}s`);
        const stray = cuts.filter((t) => t > start + 0.2 && t < b.screen.visible_until - 0.2);
        if (stray.length) finding(b.beat, 'result-hold', 'warn', `unexpected visual change(s) at ${stray.map((t) => t.toFixed(2)).join(', ')}s inside the result hold (not in the edit decision list); confirm the result stays readable.`);
        if (Number.isFinite(named) && Number.isFinite(visible) && named < visible - 0.1) finding(b.beat, 'narration-order', 'fail', `the line names "${b.result.keyword.w}" at ${named.toFixed(2)}s, ${((visible - named) * 1000).toFixed(0)} ms before the picture shows the result (${visible.toFixed(2)}s).`);
        if (Number.isFinite(named) && named > b.screen.visible_until) finding(b.beat, 'narration-order', 'fail', `the line names "${b.result.keyword.w}" after the screen is gone.`);
      }
    }
  }
  // A picture that runs uniformly early or late against the edit decision list (for example a lead-in the compositor did not
  // pad) moves every cut by the same amount. Each cut can then fall outside the per-beat match window and only warn, so
  // check the offset across all beats: most cuts agreeing on one non-zero offset means the cue sheet does not describe the file.
  if (edlDeltas.length >= 3) {
    const sorted = edlDeltas.map((d) => d.delta).sort((x, y) => x - y);
    const median = sorted[Math.floor(sorted.length / 2)];
    const agreeing = edlDeltas.filter((d) => Math.abs(d.delta - median) <= 0.1);
    if (Math.abs(median) > 0.1 && agreeing.length * 3 >= edlDeltas.length * 2) {
      fail(`the encoded picture is uniformly ${Math.abs(median * 1000).toFixed(0)} ms ${median < 0 ? 'early' : 'late'} against the edit decision list (${agreeing.length} of ${edlDeltas.length} scene cuts agree: ${agreeing.slice(0, 5).map((d) => `${d.beat} ${(d.delta * 1000).toFixed(0)} ms`).join(', ')}); every action is off its spoken word by the same amount. Check the compositor lead-in and rebuild the cue sheet from this file's compose map.`);
    }
  }
  if (!narratedActions) fail('the cue sheet has no narrated action: a product screencast must tie at least one cursor action to a spoken word (label the click, e.g. h.click(loc, { label: "Approve" }), and name it in the line).');

  // ---- A/V sync
  const av = { method: null };
  const flat = beats.flatMap((b) => (b.narration?.words || []).map((w) => ({ ...w, beat: b.beat })));
  if (!audio) { fail('candidate has no audio stream.'); }
  else {
    performed.add('av-sync');
    const startOff = Math.abs((Number(audio.start_time) || 0) - (Number(video.start_time) || 0)) * 1000;
    const lenOff = Math.abs((Number(audio.duration) || duration) - (Number(video.duration) || duration)) * 1000;
    av.containerStartOffsetMs = L.round(startOff, 1); av.containerLengthDifferenceMs = L.round(lenOff, 1);
    if (startOff > T.driftMaxMs) fail(`audio and video streams start ${startOff.toFixed(0)} ms apart (max ${T.driftMaxMs} ms).`);
    if (lenOff > 250) fail(`audio and video stream lengths differ by ${lenOff.toFixed(0)} ms (max 250 ms).`);
    const derivedPath=join(root,'qa','derived-audio-clock.json');
    const alignmentPath = existsSync(derivedPath) ? derivedPath : join(root, 'qa', 'encoded-alignment.json');
    if (existsSync(alignmentPath)) {
      try {
        const jobPath = join(root, 'job.json');
        const allowAsrAnchored = existsSync(jobPath) && JSON.parse(readFileSync(jobPath, 'utf8'))?.clockPolicy?.allowAsrAnchored === true;
        const bindings={
          takeSha256: candidateSha, scriptSha256: sha(join(root, 'story', 'locked-script.txt')), allowAsrAnchored,
        };
        const document=JSON.parse(readFileSync(alignmentPath,'utf8'));
        const measured=alignmentPath===derivedPath ? measureDerivedAudioClock(readDerivedAudioClock(root,document,bindings),flat,T.driftMaxMs) : L.measureWordSync(document,flat,bindings,T.driftMaxMs);
        Object.assign(av, measured, { alignment: { path: alignmentPath===derivedPath?'qa/derived-audio-clock.json':'qa/encoded-alignment.json', sha256: sha(alignmentPath) } });
        measured.errors.forEach(fail);
      } catch (e) { fail(`forced alignment: ${e.message}`); }
    } else {
      const jobPath = join(root, 'job.json');
      if (existsSync(jobPath) && JSON.parse(readFileSync(jobPath, 'utf8')).syncClock === 'forced-aligner') fail('missing qa/encoded-alignment.json; ai.ps1 align is required, Whisper is only a transcript check.');
      const sd = await ffmpegAsync(['-i', candidate, '-vn', '-af', 'silencedetect=noise=-35dB:d=0.2', '-f', 'null', '-']);
      const onsets = L.parseSilenceEnds(sd.stderr);
      const deltas = []; const times = [];
      beats.forEach((b, i) => {
        const w0 = b.narration?.words?.[0]; if (!w0) return;
        const prevEnd = i > 0 ? (beats[i - 1].narration?.words?.at(-1)?.end ?? 0) : 0;
        if (w0.start - prevEnd < 0.3) return;
        const near = onsets.filter((t) => Math.abs(t - w0.start) <= 0.6).sort((x, y) => Math.abs(x - w0.start) - Math.abs(y - w0.start))[0];
        if (near !== undefined) { deltas.push((near - w0.start) * 1000); times.push(w0.start); }
      });
      av.method = 'speech-onset'; av.anchors = deltas.length;
      if (deltas.length < 3) { skip('av-sync-word-offset', `only ${deltas.length} speech onsets with a clear pause before them; run ASR on the encoded audio (ai.ps1 transcribe <candidate> --engine whisper --json-out qa\\encoded-asr.json) for a word-level A/V check.`); }
      else {
        const stats = L.offsetStats(deltas, times); Object.assign(av, stats);
        if (Math.abs(stats.offsetMs) > T.onsetOffsetMaxMs) fail(`speech onsets sit ${stats.offsetMs} ms from the cue-sheet words (onset estimate; max +-${T.onsetOffsetMaxMs} ms).`);
        if (Math.abs(stats.driftMs) > T.driftMaxMs) fail(`A/V drift ${stats.driftMs} ms from the start of the program to its end (max +-${T.driftMaxMs} ms).`);
        skip('av-sync-asr-on-encoded', 'no forced alignment supplied; legacy diagnostic speech-onset estimate only (120 ms). Whisper timestamps are not a word clock; run ai.ps1 align for word-sync.');
      }
    }
  }

  // ---- text clipping (OCR) when available
  const tess = process.env.MEDIA_SYNC_TESSERACT === 'none' ? { status: 1 } : run(process.env.MEDIA_SYNC_TESSERACT || 'tesseract', ['--version']);
  if (tess.status === 0 && !tess.error) {
    performed.add('text-clipping');
    const dir = mkdtempSync(join(os.tmpdir(), 'sync-ocr-'));
    try {
      for (const b of beats.filter((x) => x.screen?.kind === 'screen')) {
        const t = Math.max(b.slot_start + 0.5, Math.min(b.screen.visible_until - 0.3, (b.result?.visible_at ?? b.slot_start) + 0.8));
        const png = join(dir, `${b.beat}.png`);
        run('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-ss', String(t), '-i', candidate, '-frames:v', '1', png]);
        if (!existsSync(png)) continue;
        const o = run(process.env.MEDIA_SYNC_TESSERACT || 'tesseract', [png, 'stdout', '-l', 'eng', 'tsv']);
        const clipped = L.clippedWords(o.stdout || '', W, H);
        if (clipped.length) finding(b.beat, 'text-clipping', 'warn', `text touching the frame edge at ${t.toFixed(1)}s: ${clipped.slice(0, 4).map((c) => `"${c.text}"`).join(', ')}. A Recast punch-in can crop legitimately; confirm in the watch pass.`);
      }
    } finally { rmSync(dir, { recursive: true, force: true }); }
  } else skip('text-clipping', 'tesseract (OCR) is not installed or not on PATH; text clipping was not machine-checked. Inspect sampled frames in the final watch pass.');

  skip('cursor-lead', 'the cursor arriving just before the spoken word is not measured; only the action instant is gated.');
  skip('cursor-continuity-across-cuts', 'cursor position consistency across cuts is not measured; judge it in the final watch pass.');
  skip('action-visual-confirmation', 'the click or state change is not detected in the encoded pixels; action times come from the capture receipt through the edit decision list, and the picture is bound to the capture by validate-encoded-picture.mjs.');
  skip('rendered-audio-and-picture-review', 'a person must still watch and listen to the exact encoded file against the cue sheet (media-studio-qa final check); this gate does not replace it.');
  avReport = av;
}

const ok = errors.length === 0 && !!candidateSha;
const report = {
  generator: 'media-studio/validate-sync',
  schemaVersion: '1.0.0',
  ok,
  degraded: degraded.length > 0,
  errors,
  warnings,
  candidate: { path: candidate, sha256: candidateSha, bytes: candidateBytes, durationSeconds: duration, width: W, height: H },
  cueSheet: cueSheet ? { path: relative(root, cuePath).replace(/\\/g, '/'), sha256: existsSync(cuePath) ? sha(cuePath) : null, mode: cueSheet.mode, durationSeconds: cueSheet.durationSeconds } : null,
  thresholds: T,
  precision: { allWordLevel: degraded.length === 0, degradedBeats: degraded.map((b) => b.beat) },
  av: avReport,
  freezes: freezeReport,
  beats: [...beatRecs.values()],
  checks: { performed: [...performed], notPerformed },
  measuredAt: new Date().toISOString(),
};
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ ok, candidateSha256: candidateSha, errors, warnings, notPerformed: notPerformed.map((n) => n.check), out: relative(root, outPath).replace(/\\/g, '/') }, null, 2));
process.exit(ok ? 0 : 1);
