// Narration-to-visual sync tooling: sync-lib timing rules, build-cue-sheet.mjs, validate-sync.mjs (VIDEO-SYNC-DIRECTIVE 2026-10-15).
// Run: node --test packages/media-studio/tests/video-sync.test.mjs   (the gate fixtures need ffmpeg/ffprobe; they are 320x200 and short)
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const L = await import(pathToFileURL(join(pkg, 'kit', 'screencast', 'sync-lib.mjs')).href);
const cueBuilder = join(pkg, 'scripts', 'build-cue-sheet.mjs');
const syncGate = join(pkg, 'scripts', 'validate-sync.mjs');
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const run = (script, args, env = {}) => { const r = spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', windowsHide: true, env: { ...process.env, ...env } }); return { code: r.status, out: `${r.stdout}${r.stderr}` }; };
const hasFfmpeg = (() => { try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore', windowsHide: true }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore', windowsHide: true }); return true; } catch { return false; } })();
const ff = (args) => execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-threads', '2', ...args], { stdio: ['ignore', 'ignore', 'inherit'], windowsHide: true, timeout: 120000 });
const scratch = mkdtempSync(join(tmpdir(), 'video-sync-'));
test.after(async () => { await new Promise((r) => setTimeout(r, 800)); rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); });
const write = (p, data) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2)); };

// ------------------------------------------------------------------ sync-lib

test('ASR parsing: word timestamps, segment-only degradation, flat word arrays, offset onto the program timeline', () => {
  const whisper = { segments: [{ start: 0, end: 2, text: 'Click approve now', words: [{ start: 0.1, end: 0.4, word: ' Click' }, { start: 0.5, end: 1, word: ' approve' }, { start: 1.2, end: 1.6, word: ' now' }] }] };
  const w = L.parseAsrWords(whisper, { offset: 10 });
  assert.equal(w.precision, 'word');
  assert.deepEqual(w.words.map((x) => [x.w, x.start]), [['Click', 10.1], ['approve', 10.5], ['now', 11.2]]);
  const seg = L.parseAsrWords({ segments: [{ start: 0, end: 3, text: 'one two three four' }] });
  assert.equal(seg.precision, 'segment');
  assert.equal(seg.words.length, 4);
  assert.ok(seg.words[0].start === 0 && Math.abs(seg.words.at(-1).end - 3) < 0.01);
  assert.equal(L.parseAsrWords({ words: [{ word: 'a', start: 0, end: 0.2 }] }).precision, 'word');
  assert.equal(L.parseAsrWords({ text: 'plain transcript only' }).precision, 'none');
});

test('keyword matching is stem tolerant and skips filler words', () => {
  assert.ok(L.wordMatches('approved', 'approve') && L.wordMatches('sending', 'send') && !L.wordMatches('plan', 'queue'));
  const words = L.spreadWords('Now we open the queue and approve the plan', 0, 4);
  const hit = L.findKeywordWord(words, ['approve']);
  assert.equal(hit.w, 'approve');
  assert.equal(L.firstContentWord(L.spreadWords('And then the queue opens', 0, 2)).w, 'queue');
  assert.deepEqual(L.keywordsFromLabel('Approve the plan'), ['approve', 'plan']);
});

test('alignment: too early freezes the first frame, too late trims the head, impossible cases demand recapture', () => {
  const edit = { trimStart: 0, speed: 1, skip: [], headHold: 0, srcSeconds: 20 };
  const early = L.planAlignment({ edit, actionClipTime: 3, targetSlotSeconds: 4 });
  assert.equal(early.edit.headHold, 1); assert.equal(early.deltaSeconds, 1);
  const late = L.planAlignment({ edit, actionClipTime: 5, targetSlotSeconds: 3 });
  assert.equal(late.edit.trimStart, 2);
  const tooEarly = L.planAlignment({ edit, actionClipTime: 2, targetSlotSeconds: 6 });
  assert.match(tooEarly.error, /may freeze its first frame/);
  const tooLate = L.planAlignment({ edit, actionClipTime: 2, targetSlotSeconds: 0.5 });
  assert.match(tooLate.error, /pointer approach/);
  const sped = L.planAlignment({ edit: { ...edit, speed: 2 }, actionClipTime: 6, targetSlotSeconds: 2 });
  assert.equal(sped.edit.trimStart, 2, '2x playback: 1 s earlier in the slot is 2 s of source');
  assert.match(L.planAlignment({ edit: { ...edit, skip: [[2, 4]] }, actionClipTime: 3, targetSlotSeconds: 2 }).error, /skipped range/);
});

test('edit mapping and voice-first slot start', () => {
  const edit = { trimStart: 1, trimEnd: 20, speed: 1, skip: [[5, 7]], headHold: 0.5, srcSeconds: 20 };
  assert.equal(L.clipToSlot(edit, 2), 1.5);          // 0.5 hold + (2 - 1)
  assert.equal(L.clipToSlot(edit, 8), 5.5);          // 0.5 + (4 kept before the skip) + (8 - 7)
  assert.equal(L.clipToSlot(edit, 6), null);         // dropped
  assert.equal(L.slotStartFor({ segmentStart: 10, firstWordStart: 10.1, prevSpeechEnd: 9 }), 9.8);
  assert.equal(L.slotStartFor({ segmentStart: 10, firstWordStart: 10.1, prevSpeechEnd: 9.9 }), 9.95, 'never before the previous line has finished');
  assert.equal(L.slotStartFor({ segmentStart: 10, firstWordStart: 11, prevSpeechEnd: 9 }), 10, 'never later than the segment start');
});

test('encoded measurements: word alignment, drift, freezes, dropped frames, clipped text', () => {
  const cue = L.spreadWords('one two three four five six seven eight nine', 0, 9);
  const asr = cue.map((w) => ({ ...w, start: w.start + 0.1 * (w.start / 9), end: w.end }));
  const pairs = L.alignWords(cue, asr);
  assert.equal(pairs.length, 9);
  const stats = L.offsetStats(pairs.map(([i, j]) => (asr[j].start - cue[i].start) * 1000), pairs.map(([i]) => cue[i].start));
  assert.ok(stats.driftMs > 50 && stats.driftMs < 100, `drift ${stats.driftMs}`);
  assert.deepEqual(L.parseFreezes('[freezedetect @ 0x1] lavfi.freezedetect.freeze_start: 3\n[freezedetect @ 0x1] lavfi.freezedetect.freeze_duration: 5\n[freezedetect @ 0x1] lavfi.freezedetect.freeze_end: 8\n'), [{ start: 3, end: 8, duration: 5 }]);
  assert.equal(L.parseFreezes('lavfi.freezedetect.freeze_start: 12', 20)[0].duration, 8, 'a freeze still open at end of file closes there');
  assert.equal(L.droppedFrames([0, 0.0333, 0.0667, 0.1667, 0.2], 30).dropped, 2);
  const tsv = 'level\tleft\ttop\twidth\theight\tconf\ttext\n5\t0\t100\t60\t20\t95\tApprove\n5\t300\t100\t60\t20\t95\tfine\n5\t1590\t200\t40\t20\t90\tclipp\n';
  assert.deepEqual(L.clippedWords(tsv, 1600, 1000).map((w) => w.text), ['Approve', 'clipp']);
});

// ------------------------------------------------------------------ build-cue-sheet

function cueJob(name, { asr = 'word', mapped = false, plan = null, headTrim = 0 } = {}) {
  const root = join(scratch, name);
  write(join(root, 'story', 'narration-timeline.json'), { durationSeconds: 9, segments: [
    { id: 'S01', scene: 'S01', text: 'Welcome to the approval queue', startSeconds: 0, durationSeconds: 3 },
    { id: 'S02', scene: 'S02', text: 'Click approve and the plan is approved', startSeconds: 3, durationSeconds: 6 },
  ] });
  if (asr === 'word') {
    write(join(root, 'voice', 'asr', 'S01.json'), { segments: [{ start: 0, end: 2.4, text: 'Welcome to the approval queue', words: [{ start: 0.5, end: 0.9, word: 'Welcome' }, { start: 0.9, end: 1.0, word: 'to' }, { start: 1.0, end: 1.1, word: 'the' }, { start: 1.2, end: 1.7, word: 'approval' }, { start: 1.8, end: 2.2, word: 'queue' }] }] });
    write(join(root, 'voice', 'asr', 'S02.json'), { segments: [{ start: 0.4, end: 4, text: 'Click approve and the plan is approved', words: [{ start: 0.4, end: 0.7, word: 'Click' }, { start: 0.7, end: 1.2, word: 'approve' }, { start: 1.3, end: 1.4, word: 'and' }, { start: 1.4, end: 1.5, word: 'the' }, { start: 1.5, end: 1.8, word: 'plan' }, { start: 1.8, end: 1.9, word: 'is' }, { start: 3.0, end: 3.5, word: 'approved' }] }] });
  } else if (asr === 'segment') {
    write(join(root, 'voice', 'asr', 'S01.json'), { segments: [{ start: 0.5, end: 2.2, text: 'Welcome to the approval queue' }] });
    write(join(root, 'voice', 'asr', 'S02.json'), { segments: [{ start: 0.4, end: 3.5, text: 'Click approve and the plan is approved' }] });
  }
  write(join(root, 'capture', 'manifest.json'), { clips: [{ id: 'S02', file: 'clips/S02.webm', segments: ['S02'], trimStart: 0.5 }] });
  // headTrim: Recast's blank lead-in trim in seconds (record-job.mjs records it); null leaves it out, like a receipt
  // written before the kit measured it. Receipt times stay on the raw recording clock either way.
  write(join(root, 'capture', 'receipt.json'), { clips: { S02: { file: 'clips/S02.webm', recast: 'full', actionClock: 'recording-start',
    ...(headTrim === null ? {} : { recastHeadTrimSeconds: headTrim, recastHeadTrimMethod: 'test' }), actions: [
    { t: 1, type: 'move', x: 100, y: 100 }, { t: 2.15, type: 'click', tStart: 2.1, x: 640, y: 300, label: 'Approve', target: 'Approve' },
    { t: 3.0, type: 'expect', label: 'Plan approved' }], expectations: [{ label: 'Plan approved', observed: true, at: 2.2, observedAt: 3.0 }] } } });
  if (plan) write(join(root, 'story', 'cue-plan.json'), plan);
  if (mapped) write(join(root, 'output', 'x-compose-map.json'), { generator: 'media-studio/compose-screencast', groups: [
    { segments: ['S01'], startSeconds: 0, needSeconds: 3, clipId: 'S01-card', file: 'clips/S01-card.png', isImage: true, edit: null, fit: 'hold' },
    { segments: ['S02'], startSeconds: 3, needSeconds: 6, clipId: 'S02', file: 'clips/S02.webm', srcSeconds: 9, fit: 'cut', edit: { trimStart: 0.5, trimEnd: 8, speed: 1, skip: [], headHold: 1, srcSeconds: 8 } }] });
  return root;
}
const readCue = (root) => JSON.parse(readFileSync(join(root, 'plan', 'cue-sheet.json'), 'utf8'));

test('cue sheet (plan mode) joins ASR words, receipt actions and manifest hints per beat', () => {
  const root = cueJob('cue-plan');
  const r = run(cueBuilder, [root]); assert.equal(r.code, 0, r.out);
  const cue = readCue(root);
  assert.equal(cue.mode, 'plan');
  assert.equal(cue.beats.length, 2);
  const s02 = cue.beats[1];
  assert.equal(s02.narration.precision, 'word');
  assert.equal(s02.narration.words[1].start, 3.7, 'per-line ASR time is offset by the line start');
  assert.equal(s02.narration.firstContentWord.w, 'Click');
  const a = s02.actions[0];
  assert.deepEqual([a.kind, a.label, a.narrated], ['click', 'Approve', true]);
  assert.equal(a.clip_time, 2.1);
  assert.equal(a.action_time, null, 'plan mode has no edit decision list yet');
  assert.equal(a.action_time_natural, 4.6, 'slot start 3 + (click 2.1 - trimStart 0.5)');
  assert.equal(a.keyword.w, 'approve');
  assert.equal(a.keyword.start, 3.7);
  assert.equal(s02.result.label, 'Plan approved');
  assert.equal(s02.result.keyword.w, 'approved');
  assert.equal(s02.screen.kind, 'screen');
  assert.equal(s02.screen.clip, 'S02');
  assert.equal(cue.beats[0].screen.kind, 'card');
  assert.equal(cue.precision.allWordLevel, true);
  for (const k of ['t_start', 't_end', 'screen', 'actions', 'expected_ui_state', 'camera', 'transition']) assert.ok(k in s02, `row has ${k}`);
});

test('cue sheet (mapped mode) puts action and result times on the program timeline through the compose edit list', () => {
  const root = cueJob('cue-mapped', { mapped: true });
  const r = run(cueBuilder, [root]); assert.equal(r.code, 0, r.out);
  const cue = readCue(root);
  assert.equal(cue.mode, 'mapped');
  const s02 = cue.beats[1];
  assert.equal(s02.actions[0].action_time, 5.6, '3 + 1 s head hold + (2.1 - 0.5)');
  assert.equal(s02.result.visible_at, 6.5);
  assert.equal(s02.screen.visible_until, 9);
  assert.ok(cue.inputs.composeMap.sha256);
});

test('clip clock: Recast head trim maps raw recording times onto the clip, and an unknown clock is refused', () => {
  assert.deepEqual(L.clipClock({ recast: 'full', recastHeadTrimSeconds: 2.5 }).offset, 2.5);
  assert.equal(L.toClipTime({ recast: 'full', recastHeadTrimSeconds: 2.5 }, 14.18), 11.68, 'Revolva S05: the click logged at 14.18 s plays at 11.68 s');
  assert.equal(L.toClipTime({ recast: 'full', recastHeadTrimSeconds: 0.3 }, 0.1), 0, 'an event inside the trimmed lead-in clamps to the first frame');
  assert.equal(L.clipClock({ recast: 'skipped' }).offset, 0, 'a raw copy keeps the recording clock');
  assert.equal(L.clipClock({ recast: 'fallback' }).offset, 0);
  assert.equal(L.clipClock({ recast: 'full', actionClock: 'clip' }).offset, 0);
  assert.equal(L.clipClock({ recast: 'full' }).offset, null, 'a Recast render with no recorded trim has no known clock');
  assert.match(L.clipClock({ recast: 'noZoom' }).source, /backfill-head-trim/);
  assert.equal(L.toClipTime({ recast: 'full' }, 3), null);
});

test('cue sheet subtracts the Recast head trim from action and result times', () => {
  const root = cueJob('cue-trim', { mapped: true, headTrim: 0.6 });
  const r = run(cueBuilder, [root]); assert.equal(r.code, 0, r.out);
  const s02 = readCue(root).beats[1];
  assert.equal(s02.clip_clock.offset_seconds, 0.6);
  assert.equal(s02.actions[0].clip_time, 1.5, 'click logged at 2.1 s on the recording clock, minus the 0.6 s trim');
  assert.equal(s02.actions[0].action_time, 5, '3 + 1 s head hold + (1.5 - 0.5)');
  assert.equal(s02.result.clip_time, 2.4);
  assert.equal(s02.result.visible_at, 5.9);
});

test('cue sheet refuses a Recast clip whose receipt has no head trim instead of timing it on the wrong clock', () => {
  const root = cueJob('cue-no-trim', { headTrim: null });
  const r = run(cueBuilder, [root]);
  assert.equal(r.code, 1, r.out);
  assert.match(JSON.parse(r.out).errors[0], /^S02: clip S02: recast "full" render with no recastHeadTrimSeconds/);
  assert.deepEqual(readCue(root).beats[1].actions, [], 'no action is placed on an unknown clock');
});

test('cue sheet flags segment-level and missing ASR as degraded and keeps the cue-plan overrides', () => {
  const seg = cueJob('cue-segment', { asr: 'segment' });
  assert.equal(run(cueBuilder, [seg]).code, 0);
  let cue = readCue(seg);
  assert.equal(cue.beats[1].narration.precision, 'segment');
  assert.equal(cue.precision.allWordLevel, false);
  assert.match(cue.warnings.join(' '), /degraded timing precision/);
  const none = cueJob('cue-none', { asr: 'none', plan: { beats: { S02: { actions: [{ label: 'Approve', keywords: ['plan'] }], result: { label: 'Plan approved' }, expectedState: 'Approved badge on the plan', camera: 'punch-in on Approve', transition: 'cut' } } } });
  assert.equal(run(cueBuilder, [none]).code, 0);
  cue = readCue(none);
  assert.equal(cue.beats[1].narration.precision, 'estimate');
  assert.equal(cue.beats[1].actions[0].keyword.matched, 'plan', 'cue-plan keywords override the label');
  assert.deepEqual([cue.beats[1].expected_ui_state, cue.beats[1].camera, cue.beats[1].transition], ['Approved badge on the plan', 'punch-in on Approve', 'cut']);
  assert.equal(run(cueBuilder, [join(scratch, 'does-not-exist')]).code, 1);
});

// ------------------------------------------------------------------ sync gate on real encoded fixtures

/**
 * A 15 s (or longer) 320x200 candidate whose cuts, tone-burst "speech" and cue sheet agree, then bent by `v`.
 * Beats: S01 card 0-3, S02 screen 3-8 (click "approve" 4.6, result 6.0, named 6.2), S03 screen 8-12 (click "send" 8.8,
 * result 10.1, named 10.3), S04 card 12-15.
 */
function gateFixture(name, v = {}) {
  const root = join(scratch, name);
  const cut = v.cuts || [0, 3, 8, 12, 15];
  const total = cut.at(-1);
  const s04at = v.s04at ?? 12.4; // where the closing line starts (a longer S03 pushes it later)
  const speech = [[0.5, 2.5], [3.4, 6.6], [8.4, 10.6], [s04at, s04at + 1.6]];
  // pictureShift moves every internal cut of the encoded picture while the cue sheet keeps the planned times.
  const pcut = cut.map((t, i) => (i === 0 || i === cut.length - 1 ? t : t + (v.pictureShift || 0)));
  const dur = (i) => (pcut[i + 1] - pcut[i]).toFixed(3);
  const sources = [`color=c=blue:s=320x200:r=30:d=${dur(0)}`, `testsrc2=s=320x200:r=30:d=${dur(1)}`, `mandelbrot=s=320x200:r=30`, `color=c=0x303030:s=320x200:r=30:d=${dur(3)}`];
  const args = [];
  sources.forEach((s, i) => { if (i === 2) args.push('-f', 'lavfi', '-t', dur(2), '-i', s); else args.push('-f', 'lavfi', '-i', s); });
  const tone = speech.map(([a, b]) => `between(t,${a},${b})`).join('+');
  args.push('-f', 'lavfi', '-i', `sine=f=300:d=${total}`);
  // stillFrom: S03's picture stops changing at that program time (last frame cloned): an exact-frame freeze to the cut.
  const still = v.stillFrom != null ? `[2:v]trim=duration=${(v.stillFrom - pcut[2]).toFixed(3)},setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=${(pcut[3] - v.stillFrom).toFixed(3)}[v2];` : '';
  const vFilter = `${still}[0:v][1:v]${still ? '[v2]' : '[2:v]'}[3:v]concat=n=4:v=1:a=0,format=yuv420p[v]`;
  let aFilter = `[4:a]volume=eval=frame:volume='if(gt(${tone},0),0.8,0)'${v.audioFilter ? ',' + v.audioFilter : ''}[a]`;
  mkdirSync(join(root, 'story'), { recursive: true }); mkdirSync(join(root, 'qa'), { recursive: true }); mkdirSync(join(root, 'plan'), { recursive: true });
  const candidate = join(root, 'candidate.mp4');
  ff([...args, '-filter_complex', `${vFilter};${aFilter}`, '-map', '[v]', '-map', '[a]', '-t', String(total), '-c:v', 'libx264', '-preset', 'ultrafast', '-g', String(v.gop ?? 30), ...(v.gop ? ['-keyint_min', String(v.gop)] : []), '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', candidate]);
  const W = (s, a, b) => L.spreadWords(s, a, b);
  const s01 = W('Welcome to the approval queue today', 0.5, 2.5);
  const s02 = [['Open', 3.4, 3.7], ['the', 3.7, 3.8], ['plan', 3.8, 4.1], ['and', 4.3, 4.5], ['approve', 4.6, 5.0], ['it', 5.0, 5.1], ['The', 5.6, 5.7], ['plan', 5.7, 6.0], ['is', 6.0, 6.1], ['approved', 6.2, 6.6]].map(([w, start, end]) => ({ w, start, end }));
  const s03 = [['Now', 8.4, 8.7], ['send', 8.8, 9.1], ['the', 9.1, 9.2], ['report', 9.2, 9.6], ['The', 10.0, 10.1], ['report', 10.1, 10.2], ['is', 10.2, 10.3], ['sent', 10.3, 10.6]].map(([w, start, end]) => ({ w, start, end }));
  const s04 = W('Thanks for watching today', s04at, s04at + 1.6);
  const fcw = (ws) => { const f = L.firstContentWord(ws); return f; };
  const timeline = { durationSeconds: total, segments: ['S01', 'S02', 'S03', 'S04'].map((id, i) => ({ id, scene: id, text: id, startSeconds: cut[i], durationSeconds: cut[i + 1] - cut[i] })) };
  write(join(root, 'story', 'narration-timeline.json'), timeline);
  const kw = (ws, w) => { const x = ws.find((y) => y.w.toLowerCase() === w); return { w: x.w, start: x.start, end: x.end, matched: w }; };
  const act = (label, ws, word, at) => ({ kind: 'click', label, target: label, narrated: true, keywords: [word], clip_time: 2, action_time: at, keyword: kw(ws, word) });
  const screen = (clip, from, until, changes = true) => ({ clip, kind: clip.startsWith('card') ? 'card' : 'screen', visible_from: from, visible_until: until, changes_from_previous: changes });
  const s02from = v.s02from ?? cut[1];
  const beats = [
    { beat: 'S01', slot_start: 0, slot_end: cut[1], narration: { words: s01, precision: 'word', firstContentWord: fcw(s01) }, screen: screen('card-1', 0, cut[1], false), actions: [], result: null },
    { beat: 'S02', slot_start: s02from, slot_end: cut[2], narration: { words: s02, precision: v.precision || 'word', firstContentWord: fcw(s02) }, screen: screen('S02', s02from, cut[2]), actions: [act('Approve', s02, 'approve', 4.6 + (v.clickShift || 0))], result: { label: 'Plan approved', visible_at: 6.0, keyword: kw(s02, 'approved') } },
    { beat: 'S03', slot_start: cut[2], slot_end: cut[3], narration: { words: s03, precision: 'word', firstContentWord: fcw(s03) }, screen: screen('S03', cut[2], cut[3]), actions: [act('Send', s03, 'send', 8.8)], result: { label: 'Report sent', visible_at: 10.1, keyword: kw(s03, 'sent') } },
    { beat: 'S04', slot_start: cut[3], slot_end: total, narration: { words: s04, precision: 'word', firstContentWord: fcw(s04) }, screen: screen('card-2', cut[3], total), actions: [], result: null },
  ];
  if (v.noActions) for (const b of beats) { b.actions = []; b.result = null; }
  write(join(root, 'plan', 'cue-sheet.json'), { generator: 'media-studio/build-cue-sheet', schemaVersion: '1.0.0', voiceFirst: true, mode: v.mode || 'mapped', durationSeconds: total, inputs: { timeline: { path: 'story/narration-timeline.json', sha256: sha(join(root, 'story', 'narration-timeline.json')) }, composeMap: null }, precision: { allWordLevel: true }, beats });
  return { root, candidate };
}
const gate = (f, extra = []) => { const r = run(syncGate, [f.root, f.candidate, ...extra], { MEDIA_SYNC_TESSERACT: 'none' }); const report = existsSync(join(f.root, 'qa', 'sync.json')) ? JSON.parse(readFileSync(join(f.root, 'qa', 'sync.json'), 'utf8')) : null; return { ...r, report }; };
const failing = (report, check) => report.beats.flatMap((b) => b.findings.filter((x) => x.status === 'fail' && x.check === check).map((x) => ({ beat: b.beat, ...x })));

test('sync gate passes a candidate whose screens, clicks, holds and audio agree with the cue sheet, bound to its SHA-256', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const f = gateFixture('gate-pass');
  const r = gate(f);
  assert.equal(r.code, 0, r.out);
  const rep = r.report;
  assert.equal(rep.ok, true); assert.deepEqual(rep.errors, []);
  assert.equal(rep.candidate.sha256, sha(f.candidate));
  assert.equal(rep.candidate.bytes, readFileSync(f.candidate).length);
  for (const c of ['screen-on', 'action-timing', 'result-hold', 'narration-order', 'av-sync', 'frozen-frames', 'dropped-frames']) assert.ok(rep.checks.performed.includes(c), `${c} performed`);
  const notRun = rep.checks.notPerformed.map((n) => n.check);
  for (const c of ['text-clipping', 'cursor-lead', 'cursor-continuity-across-cuts', 'action-visual-confirmation', 'av-sync-asr-on-encoded']) assert.ok(notRun.includes(c), `${c} is reported as not performed`);
  assert.equal(rep.av.method, 'speech-onset');
  assert.ok(Math.abs(rep.av.offsetMs) < 60, `onset offset ${rep.av.offsetMs}`);
  const actions = rep.beats.flatMap((b) => b.findings).filter((x) => x.check === 'action-timing' && x.status === 'pass');
  assert.equal(actions.length, 2);
  assert.ok(rep.beats.find((b) => b.beat === 'S02').findings.some((x) => x.check === 'screen-on' && /scene-cut/.test(x.message)), 'the screen change was observed in the encoded picture');
});

test('sync gate fails a screen that appears after the first content word', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const f = gateFixture('gate-late-screen', { cuts: [0, 3.6, 8, 12, 15], s02from: 3.6 });
  const r = gate(f); assert.equal(r.code, 1, r.out);
  const hit = failing(r.report, 'screen-on'); assert.equal(hit.length, 1); assert.equal(hit[0].beat, 'S02');
  assert.match(hit[0].message, /after the first content word/);
});

test('sync gate fails a picture uniformly early against the edit decision list (an unpadded 0.6 s lead-in)', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const r = gate(gateFixture('gate-uniform-early', { pictureShift: -0.6 })); assert.equal(r.code, 1, r.out);
  assert.ok(r.report.errors.some((e) => /uniformly 600 ms early against the edit decision list \(3 of 3 scene cuts agree/.test(e)), r.report.errors.join('\n'));
  // each cut alone sits outside the per-beat match window, which is why the global check exists
  assert.deepEqual(failing(r.report, 'screen-on'), []);
  const late = gate(gateFixture('gate-uniform-late', { pictureShift: 0.3 })); assert.equal(late.code, 1, late.out);
  assert.ok(late.report.errors.some((e) => /uniformly 300 ms late/.test(e)), late.report.errors.join('\n'));
});

test('sync gate fails a click that lands early or late of its spoken verb, with the measured offset', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const early = gate(gateFixture('gate-early-click', { clickShift: -0.5 })); assert.equal(early.code, 1, early.out);
  assert.match(failing(early.report, 'action-timing')[0].message, /500 ms before the spoken "approve"/);
  const late = gate(gateFixture('gate-late-click', { clickShift: 0.5 })); assert.equal(late.code, 1, late.out);
  assert.match(failing(late.report, 'action-timing')[0].message, /500 ms after the spoken "approve"/);
  const edge = gate(gateFixture('gate-edge-click', { clickShift: 0.25 })); assert.equal(edge.code, 0, 'inside +-300 ms still passes: ' + edge.out);
});

test('sync gate fails a result that is held under 1.5 s after the line names it', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const f = gateFixture('gate-short-hold', { cuts: [0, 3, 7, 12, 15] });
  const cuePath = join(f.root, 'plan', 'cue-sheet.json');
  const r = gate(f); assert.equal(r.code, 1, r.out);
  const hit = failing(r.report, 'result-hold'); assert.equal(hit.length, 1);
  assert.match(hit[0].message, /needs >= 1.5s/);
  assert.ok(existsSync(cuePath));
});

test('sync gate fails audio that is late against the cue-sheet words (constant offset and progressive drift)', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const offset = gate(gateFixture('gate-offset', { audioFilter: 'adelay=300|300' })); assert.equal(offset.code, 1, offset.out);
  assert.match(offset.report.errors.join(' '), /speech onsets sit .* ms from the cue-sheet words/);
  const drift = gate(gateFixture('gate-drift', { audioFilter: 'atempo=0.97' })); assert.equal(drift.code, 1, drift.out);
  assert.match(drift.report.errors.join(' '), /A\/V drift/);
});

test('sync gate uses ASR on the encoded audio for the exact 40 ms check when supplied', { skip: !hasFfmpeg, timeout: 180000 }, () => {
  const f = gateFixture('gate-asr');
  const cue = JSON.parse(readFileSync(join(f.root, 'plan', 'cue-sheet.json'), 'utf8'));
  const asrWords = (shift) => ({ words: cue.beats.flatMap((b) => b.narration.words).map((w) => ({ word: w.w, start: w.start + shift, end: w.end + shift })) });
  write(join(f.root, 'qa', 'encoded-asr.json'), asrWords(0.01));
  let r = gate(f); assert.equal(r.code, 0, r.out);
  assert.equal(r.report.av.method, 'asr-on-encoded');
  assert.ok(!r.report.checks.notPerformed.some((n) => n.check === 'av-sync-asr-on-encoded'));
  write(join(f.root, 'qa', 'encoded-asr.json'), asrWords(0.1));
  r = gate(f); assert.equal(r.code, 1);
  assert.match(r.report.errors.join(' '), /encoded audio is 100 ms off/);
});

test('sync gate fails a long exact-frame freeze, degraded timing, a stale or plan-mode cue sheet, and a film with no narrated action', { skip: !hasFfmpeg, timeout: 240000 }, () => {
  const frozen = gate(gateFixture('gate-freeze', { cuts: [0, 3, 8, 12, 19] })); assert.equal(frozen.code, 1, frozen.out);
  assert.match(frozen.report.errors.join(' '), /exact-frame freeze .* A static scene needs a moving cursor/);
  const degraded = gateFixture('gate-degraded', { precision: 'estimate' });
  let r = gate(degraded); assert.equal(r.code, 1); assert.match(r.report.errors.join(' '), /not word-level/);
  r = gate(degraded, ['--allow-degraded']); assert.equal(r.report.degraded, true, 'diagnostic mode still marks the report degraded');
  const plan = gate(gateFixture('gate-plan-mode', { mode: 'plan' })); assert.equal(plan.code, 1); assert.match(plan.report.errors.join(' '), /plan mode: compose first/);
  const stale = gateFixture('gate-stale'); write(join(stale.root, 'story', 'narration-timeline.json'), { durationSeconds: 15, segments: [] });
  r = gate(stale); assert.equal(r.code, 1); assert.match(r.report.errors.join(' '), /cue sheet is stale/);
  const bare = gate(gateFixture('gate-no-actions', { noActions: true })); assert.equal(bare.code, 1); assert.match(bare.report.errors.join(' '), /no narrated action/);
  const missing = gateFixture('gate-no-cue'); rmSync(join(missing.root, 'plan', 'cue-sheet.json'));
  r = gate(missing); assert.equal(r.code, 1); assert.match(r.out, /missing plan\/cue-sheet.json/);
});

// ------------------------------------------------------------------ freeze gate: a declared hold is not a freeze

const hb = (beat, o = {}) => ({ beat, slot_start: o.from ?? 0, slot_end: o.until ?? 10, screen: { kind: o.kind || 'screen', visible_from: o.from ?? 0, visible_until: o.until ?? 10, changes_from_previous: o.changes ?? true }, actions: o.actions ?? [], result: o.result ?? null });

test('declared hold: from the last action or the result to the slot end; a card or read beat holds from its start; unknown timing declares nothing', () => {
  const act = (t) => ({ kind: 'click', label: 'Send', narrated: true, action_time: t });
  assert.deepEqual(L.declaredHold(hb('S02', { from: 3, until: 14, actions: [act(4.6)], result: { label: 'Plan approved', visible_at: 6 } })), { beat: 'S02', from: 6, until: 14, kind: 'after-result' });
  assert.deepEqual(L.declaredHold(hb('S02', { from: 3, until: 14, actions: [act(4.6), act(7)], result: { label: 'x', visible_at: 6 } })), { beat: 'S02', from: 7, until: 14, kind: 'after-result' }, 'the later of last action and result');
  assert.deepEqual(L.declaredHold(hb('S02', { from: 3, until: 14, actions: [act(4.6)] })), { beat: 'S02', from: 4.6, until: 14, kind: 'after-action' });
  assert.deepEqual(L.declaredHold(hb('S04', { from: 12, until: 19, kind: 'card' })), { beat: 'S04', from: 12, until: 19, kind: 'static-beat' });
  assert.equal(L.declaredHold(hb('S02', { from: 3, until: 14, actions: [act(null)] })), null, 'actions with no program time: the hold cannot be placed');
});

test('expected-change points and freeze classification: stalled where change is expected, declared hold, overlong hold, undeclared', () => {
  const act = (t) => ({ kind: 'click', label: 'Send', narrated: true, action_time: t });
  const beats = [hb('S01', { from: 0, until: 3, kind: 'card', changes: false }),
    hb('S03', { from: 8, until: 16, actions: [act(8.8)], result: { label: 'Report sent', visible_at: 10.1 } }),
    hb('S04', { from: 16, until: 26, kind: 'card' })];
  const pts = L.expectedChangePoints(beats, [{ startSeconds: 16 }]);
  assert.deepEqual(pts.map((p) => [p.beat, p.t]), [['S03', 8], ['S03', 8.8], ['S03', 10.1], ['S04', 16]], 'first beat, hold beats and the edl cut at 16 (already a beat start) are not doubled');
  const o = { beats, edl: [], maxFreezeSeconds: 4, maxHoldSeconds: 6.5 };
  const f = (start, end) => ({ start, end, duration: end - start });
  assert.equal(L.classifyFreeze(f(10.4, 16), o).verdict, 'declared-hold');
  assert.equal(L.classifyFreeze(f(8.5, 16), o).verdict, 'stalled');
  assert.deepEqual(L.classifyFreeze(f(8.5, 16), o).stalled.map((p) => p.t), [8.8, 10.1]);
  assert.equal(L.classifyFreeze(f(16, 26), o).verdict, 'overlong-hold', '10 s of card is over the 6.5 s max hold');
  assert.equal(L.classifyFreeze(f(16, 21), o).verdict, 'declared-hold');
  assert.equal(L.classifyFreeze(f(2, 6.5), o).verdict, 'undeclared', 'S01 is a card but the freeze runs into S03');
  assert.equal(L.classifyFreeze(f(9, 12), o).verdict, 'stalled', 'short freezes over a change point fail whatever their length');
  assert.equal(L.classifyFreeze(f(11, 14), o).verdict, 'ignore', 'a short freeze inside the hold is nothing');
  assert.equal(L.classifyFreeze(f(9.2, 9.9), { ...o, maxFreezeSeconds: 0.1 }).verdict, 'undeclared', 'before the result: not yet in the hold, not on a change point');
});

// gop 1000: a keyframe re-quantises a still picture and ends an exact-frame freeze, so the fixture keeps one GOP.
const holdFixture = (name, v = {}) => gateFixture(name, { cuts: [0, 3, 8, 16, 19], s04at: 16.4, stillFrom: 10.4, gop: 1000, ...v });
const editCue = (f, fn) => { const p = join(f.root, 'plan', 'cue-sheet.json'); const c = JSON.parse(readFileSync(p, 'utf8')); fn(c); write(p, c); };

test('sync gate passes a 5.6 s picture hold after the result is visible as a declared hold, and records it', { skip: !hasFfmpeg, timeout: 240000 }, () => {
  const f = holdFixture('hold-declared');
  const r = gate(f); assert.equal(r.code, 0, r.out);
  const hold = r.report.beats.find((b) => b.beat === 'S03').findings.find((x) => x.check === 'declared-hold');
  assert.equal(hold.status, 'pass');
  assert.match(hold.message, /exact-frame freeze 10\.\d\d-16\.00s \(5\.\ds\) is a declared hold: the picture is meant to stay still from 10\.10s to 16\.00s \(5\.9s, after-result\)/);
  assert.ok(r.report.checks.performed.includes('frozen-frames'));
  assert.ok(r.report.beats.find((b) => b.beat === 'S03').findings.some((x) => x.check === 'result-hold' && x.status === 'pass'), 'the 1.5 s result-hold minimum is unchanged');
});

test('sync gate fails the same still when it is stretched across a click and the result: stalled where the cue sheet expects change', { skip: !hasFfmpeg, timeout: 240000 }, () => {
  const r = gate(holdFixture('hold-stalled', { stillFrom: 8.2 })); assert.equal(r.code, 1, r.out);
  const msgs = failing(r.report, 'frozen-frames').map((x) => x.message);
  assert.ok(msgs.some((m) => /the picture is stalled where the cue sheet expects click "Send" at 8\.80s/.test(m)), msgs.join('\n'));
  assert.ok(msgs.some((m) => /stalled where the cue sheet expects result "Report sent" at 10\.10s/.test(m)), msgs.join('\n'));
  assert.ok(!msgs.some((m) => /A static scene needs/.test(m)), 'a stall is reported as a stall, not twice');
});

test('sync gate still fails a long still outside every declared hold, and a hold over the max hold (--max-hold)', { skip: !hasFfmpeg, timeout: 240000 }, () => {
  const f = holdFixture('hold-undeclared');
  editCue(f, (c) => { c.beats[2].actions[0].action_time = null; c.beats[2].result = null; }); // the cue sheet cannot place a hold in S03
  let r = gate(f); assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /beat S03: frozen-frames: exact-frame freeze 10\.\d\d-16\.00s \(5\.\ds > 4s\) outside any declared hold\. A static scene needs a moving cursor/);
  const g = holdFixture('hold-overlong');
  assert.equal(gate(g).code, 0);
  r = gate(g, ['--max-hold', '3']); assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /beat S03: frozen-frames: exact-frame freeze 10\.\d\d-16\.00s \(5\.\ds > 4s\) is inside a declared hold but longer than the 3s max hold\. A static scene needs a moving cursor/);
});
