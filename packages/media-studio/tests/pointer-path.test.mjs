// Pointer-path gate: the cursor moves with purpose (one direction per beat, no flicking, no up-and-down, no wandering,
// no scrolling past and returning). Pure JSON fixtures, no ffmpeg. Run: node --test tests/pointer-path.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const gate = join(pkg, 'scripts', 'validate-pointer-path.mjs');
const scratch = mkdtempSync(join(tmpdir(), 'pointer-path-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));
const write = (p, data) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2)); };
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const run = (root, args = []) => {
  const r = spawnSync(process.execPath, [gate, root, ...args], { encoding: 'utf8', windowsHide: true });
  const report = existsSync(join(root, 'qa', 'pointer-path.json')) ? JSON.parse(readFileSync(join(root, 'qa', 'pointer-path.json'), 'utf8')) : null;
  return { code: r.status, out: `${r.stdout}${r.stderr}`, report };
};

// ---- event builders, shaped like record-lib.mjs (approach() logs three eased moves; click/point/expect follow)
const ease = (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2);
class Take {
  constructor(t = 1) { this.t = t; this.events = []; this.at = { x: 300, y: 300 }; }
  approach(to) {
    const from = this.at;
    for (let i = 1; i <= 3; i++) { this.t += 0.15; this.events.push({ t: +this.t.toFixed(3), type: 'move', x: Math.round(from.x + (to.x - from.x) * ease(i / 3)), y: Math.round(from.y + (to.y - from.y) * ease(i / 3)) }); }
    this.at = to; this.t += 0.25; return this;
  }
  moves(...pts) { for (const [x, y] of pts) { this.t += 0.15; this.events.push({ t: +this.t.toFixed(3), type: 'move', x, y }); } this.at = { x: pts.at(-1)[0], y: pts.at(-1)[1] }; return this; }
  click(label) { this.t += 0.1; this.events.push({ t: +(this.t + 0.06).toFixed(3), type: 'click', x: this.at.x, y: this.at.y, label, target: label, tStart: +this.t.toFixed(3) }); this.t += 0.3; return this; }
  point(label) { this.t += 0.1; this.events.push({ t: +this.t.toFixed(3), type: 'point', x: this.at.x, y: this.at.y, label, target: label, tStart: +this.t.toFixed(3) }); this.t += 0.3; return this; }
  tap(label, x, y) { this.t += 0.1; this.at = { x, y }; this.events.push({ t: +(this.t + 0.05).toFixed(3), type: 'tap', x, y, label, target: label, tStart: +this.t.toFixed(3) }); this.t += 0.3; return this; }
  expect(label) { this.events.push({ t: +this.t.toFixed(3), type: 'expect', label }); return this; }
  goto() { this.events.push({ t: +this.t.toFixed(3), type: 'goto', url: 'http://127.0.0.1/x' }); this.t += 0.5; return this; }
  wheel(dy, n = 6) { for (let i = 0; i < n; i++) { this.t += 0.07; this.events.push({ t: +this.t.toFixed(3), type: 'wheel', dy }); } this.t += 0.3; return this; }
}
const clipRec = (take, extra = {}) => ({ file: 'clips/C1.webm', segments: ['C1'], recast: 'full', actionClock: 'recording-start', recastHeadTrimSeconds: 0.5, recastHeadTrimMethod: 'test', clipSeconds: 30, actions: take.events, expectations: [], ...extra });

function job(name, { clips, cuePlan = null, storyboard = null, cueSheet = null } = {}) {
  const root = join(scratch, name);
  write(join(root, 'capture', 'receipt.json'), { schemaVersion: '1.0.0', generator: 'media-studio/record-job', clips });
  if (cuePlan) write(join(root, 'story', 'cue-plan.json'), cuePlan);
  if (storyboard) write(join(root, 'story', 'storyboard.json'), storyboard);
  if (cueSheet) write(join(root, 'plan', 'cue-sheet.json'), cueSheet);
  return root;
}
const check = (w, name) => w.findings.find((f) => f.check === name);

// ---- PASS

test('PASS: eased approach, click, expect, then one approach and a point', () => {
  const t = new Take().goto().approach({ x: 900, y: 500 }).click('open dialog').expect('dialog open').approach({ x: 1200, y: 200 }).point('result');
  const root = job('pass', { clips: { C1: clipRec(t) } });
  const r = run(root);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.ok, true);
  assert.equal(r.report.generator, 'media-studio/validate-pointer-path');
  const w = r.report.windows[0];
  assert.equal(w.clip, 'C1');
  assert.equal(w.approaches, 2);
  assert.equal(w.namedApproaches, 2);
  assert.equal(w.reversals, 0);
  assert.equal(w.unnamedMoves, 0);
  assert.equal(w.scrollReversals, 0);
  assert.ok(w.travelRatio >= 1 && w.travelRatio <= 1.05, `travelRatio ${w.travelRatio}`);
  assert.equal(w.allowance.source, 'default');
  assert.deepEqual(w.findings.map((f) => f.status), ['pass', 'pass', 'pass', 'pass', 'pass']);
});

test('the report binds the receipt by sha256 and records the thresholds', () => {
  const t = new Take().approach({ x: 900, y: 500 }).click('go');
  const root = job('bound', { clips: { C1: clipRec(t) } });
  const r = run(root);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.inputs.receipt.path, 'capture/receipt.json');
  assert.equal(r.report.inputs.receipt.sha256, sha(join(root, 'capture', 'receipt.json')));
  assert.equal(r.report.inputs.cueSheet, undefined);
  assert.equal(r.report.thresholds.maxReversals, 0);
  assert.equal(r.report.thresholds.maxTravelRatio, 1.35);
  assert.equal(r.report.thresholds.turnCos, -0.5);
  const o = JSON.parse(r.out.trim().split('\n').filter((l) => l.startsWith('{')).join('\n').split('\n}\n')[0].replace(/\n$/, ''));
  assert.equal(o.ok, true);
});

// ---- FAIL fixtures, one per failure class

test('FAIL flick: right, back left, right', () => {
  const t = new Take().moves([400, 300], [700, 300], [450, 300], [750, 300]).click('go');
  const r = run(job('flick', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  const w = r.report.windows[0];
  assert.equal(w.reversals, 2);
  assert.equal(check(w, 'reversals').status, 'fail');
  assert.ok(r.report.errors.some((e) => /C1: pointer reverses direction 2 time\(s\) \(allowed 0\)/.test(e)), r.report.errors.join('\n'));
});

test('FAIL up-and-down: y oscillation across four moves', () => {
  const t = new Take().moves([800, 200], [800, 500], [800, 200], [800, 500]).click('go');
  const r = run(job('updown', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  assert.equal(r.report.windows[0].reversals, 2);
  assert.match(r.report.errors.join('\n'), /pointer reverses direction 2 time\(s\)/);
});

test('FAIL scroll past and return: six +20 wheel steps then six -20 (the ABACare W01 pattern)', () => {
  const t = new Take().goto().wheel(20).wheel(-20).approach({ x: 1379, y: 274 }).click('open import dialog').expect('dialog open').approach({ x: 800, y: 570 }).point('dropzone');
  const r = run(job('scroll-return', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  const w = r.report.windows[0];
  assert.equal(w.scrollReversals, 1);
  assert.equal(w.scrollReturns, 1);
  assert.equal(w.scrollPeakPx, 120);
  assert.equal(check(w, 'scroll-reversals').status, 'fail');
  assert.equal(check(w, 'scroll-return').status, 'fail');
  assert.equal(check(w, 'reversals').status, 'pass', 'the pointer itself moved cleanly');
  const text = r.report.errors.join('\n');
  assert.match(text, /C1: scroll changes direction 1 time\(s\) \(allowed 0\): scrolling past and returning/);
  assert.match(text, /C1: scroll goes 120px and returns to its start before the next named action/);
});

test('a one-way scroll to the thing being named passes', () => {
  const t = new Take().goto().wheel(40).approach({ x: 900, y: 500 }).click('go');
  const r = run(job('scroll-one-way', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.windows[0].scrollReversals, 0);
  assert.equal(r.report.windows[0].scrollReturns, 0);
});

test('FAIL wandering: pointer moves with no click, type or point to lead to', () => {
  const t = new Take().moves([500, 300], [600, 380], [700, 420]).expect('something').approach({ x: 900, y: 500 }).click('go');
  const r = run(job('wander', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  const w = r.report.windows[0];
  assert.equal(w.approaches, 2);
  assert.equal(w.namedApproaches, 1);
  assert.equal(w.unnamedMoves, 3);
  assert.match(r.report.errors.join('\n'), /C1: 3 pointer move\(s\) do not lead to a click, type or point \(allowed 0\)/);
});

test('FAIL wandering with nothing named at all: travel has no direct distance', () => {
  const t = new Take().moves([500, 300], [650, 300], [800, 300]).expect('x');
  const r = run(job('wander-only', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  const w = r.report.windows[0];
  assert.equal(w.travelRatio, null);
  assert.equal(check(w, 'travel-ratio').measured, 'Infinity');
  assert.match(r.report.errors.join('\n'), /pointer travels \d+px with nowhere named to go/);
});

test('FAIL over-travel: a right-angle detour (ratio above 1.35) without any single reversal', () => {
  const t = new Take().moves([100, 500], [350, 250], [600, 500]).click('go');
  const r = run(job('overtravel', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  const w = r.report.windows[0];
  assert.equal(w.reversals, 0);
  assert.ok(w.travelRatio > 1.35, `ratio ${w.travelRatio}`);
  assert.equal(check(w, 'reversals').status, 'pass');
  assert.equal(check(w, 'travel-ratio').status, 'fail');
  assert.match(r.report.errors.join('\n'), /C1: pointer travels 707px for a 500px direct path \(ratio 1\.41, allowed 1\.35\)/);
});

test('FAIL missing actions: a clip without an action log cannot be judged', () => {
  const root = job('no-actions', { clips: { C1: { file: 'clips/C1.webm', segments: ['C1'], recast: 'full', clipSeconds: 8 } } });
  const r = run(root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /C1: re-record: receipt has no action log, the pointer path cannot be judged/);
});

test('FAIL a missing receipt is an error, not a pass', () => {
  const root = join(scratch, 'no-receipt'); mkdirSync(root, { recursive: true });
  const r = run(root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.out, /capture\/receipt\.json is required/);
});

// ---- touch (tap): a finger has no approach moves; the tap is the named action

test('PASS touch: taps with no pointer travel are named actions', () => {
  const t = new Take().goto().tap('open menu', 195, 700).expect('menu open').tap('pick plan', 195, 300).expect('plan open');
  const r = run(job('tap-pass', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 0, r.out);
  const w = r.report.windows[0];
  assert.equal(w.approaches, 0);
  assert.equal(w.travelPx, 0);
  assert.equal(w.directPx, 400, 'the direct polyline runs through the tap points');
  assert.equal(w.travelRatio, 0);
  assert.equal(w.unnamedMoves, 0);
  assert.ok(w.findings.every((f) => f.status === 'pass'));
});

test('a tap names the approach before it (a desktop fallback tap is a named click)', () => {
  const t = new Take().approach({ x: 900, y: 500 }); t.tap('go', 900, 500);
  const r = run(job('tap-fallback', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.windows[0].namedApproaches, 1);
  assert.equal(r.report.windows[0].unnamedMoves, 0);
});

test('FAIL touch: scrolling past and returning is still caught between taps', () => {
  const t = new Take().goto().tap('open', 195, 700).wheel(20).wheel(-20).tap('next', 195, 300);
  const r = run(job('tap-scroll', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 1, r.out);
  assert.equal(r.report.windows[0].scrollReversals, 1);
});

// ---- allowances

const flickOnce = () => new Take().moves([400, 300], [800, 300], [770, 300]).click('go');

test('a one-reversal clip fails by default', () => {
  const r = run(job('one-rev-default', { clips: { C1: clipRec(flickOnce()) } }));
  assert.equal(r.code, 1, r.out);
  assert.equal(r.report.windows[0].reversals, 1);
});

test('an allowance with a reason in the cue plan passes a one-reversal clip', () => {
  const cuePlan = { beats: { C1: { pointer: { maxReversals: 1, reason: 'the presenter overshoots the Done button and corrects once, on camera' } } } };
  const r = run(job('one-rev-allowed', { clips: { C1: clipRec(flickOnce()) }, cuePlan }));
  assert.equal(r.code, 0, r.out);
  const w = r.report.windows[0];
  assert.equal(w.allowance.source, 'cue-plan');
  assert.equal(w.allowance.maxReversals, 1);
  assert.equal(w.allowance.reason, 'the presenter overshoots the Done button and corrects once, on camera');
  assert.equal(r.report.inputs.cuePlan.path, 'story/cue-plan.json');
});

test('an allowance that loosens a default without a reason is an error', () => {
  const cuePlan = { beats: { C1: { pointer: { maxReversals: 1 } } } };
  const r = run(job('one-rev-no-reason', { clips: { C1: clipRec(flickOnce()) }, cuePlan }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /C1: pointer allowance loosens maxReversals without a reason \(cue-plan\)/);
});

test('a storyboard beat pointer allowance is accepted too', () => {
  const storyboard = { beats: [{ id: 'C1', pointer: { maxReversals: 1, reason: 'one corrective move is the point of this beat' } }] };
  const r = run(job('one-rev-storyboard', { clips: { C1: clipRec(flickOnce()) }, storyboard }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.windows[0].allowance.source, 'storyboard');
});

test('tightening an allowance needs no reason', () => {
  const t = new Take().approach({ x: 900, y: 500 }).click('go');
  const cuePlan = { beats: { C1: { pointer: { maxReversals: 0, maxTravelRatio: 1.1 } } } };
  const r = run(job('tighten', { clips: { C1: clipRec(t) }, cuePlan }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.windows[0].allowance.maxTravelRatio, 1.1);
});

test('command-line limits replace the defaults', () => {
  const r = run(job('flag-limits', { clips: { C1: clipRec(flickOnce()) } }), ['--max-reversals', '1', '--max-travel-ratio', '1.5']);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.thresholds.maxReversals, 1);
});

// ---- cue-sheet windows (mapped mode)

// Assumed mapping (build-cue-sheet 'mapped' mode): one edl group holds clip C1 from program second 10, speed 1, no head hold,
// kept source range [trimStart, srcSeconds]. A raw action time t plays at clip time t - recastHeadTrimSeconds (0.5), and at
// program time group.startSeconds + (clipTime - trimStart). Beat B1 owns program [10, 20), beat B2 owns [20, 30).
function mappedFixture(name, { trimStart = 0, early = null } = {}) {
  const t = new Take(1);
  if (early) early(t);
  t.t = Math.max(t.t, 1);
  t.approach({ x: 900, y: 500 }).click('B1 click').expect('B1 result');          // raw ~1-3 s -> program ~10.5-12.5 (B1)
  t.t = 11 + trimStart;                                                           // clip 10.5 + trimStart -> program 20.5 (B2)
  t.moves([400, 300], [700, 300], [450, 300], [750, 300]).click('B2 click');     // flick in beat B2
  const edit = { trimStart, trimEnd: null, speed: 1, skip: [], headHold: 0, srcSeconds: 30 };
  const cueSheet = {
    generator: 'media-studio/build-cue-sheet', schemaVersion: '1.0.0', mode: 'mapped', durationSeconds: 30,
    edl: [{ segments: ['B1', 'B2'], clip: 'C1', startSeconds: 10, needSeconds: 20, fit: 'cut', edit }],
    beats: [
      { beat: 'B1', slot_start: 10, slot_end: 20, screen: { clip: 'C1', kind: 'screen' }, actions: [{ kind: 'click', label: 'B1 click', clip_time: 2.7 }] },
      { beat: 'B2', slot_start: 20, slot_end: 30, screen: { clip: 'C1', kind: 'screen' }, actions: [{ kind: 'click', label: 'B2 click', clip_time: 11.7 }] },
    ],
  };
  const root = job(name, { clips: { C1: clipRec(t, { segments: ['B1', 'B2'] }) }, cueSheet });
  return root;
}

test('piecewise mapped cue sheets refuse heuristic pointer windows, including a legacy edit fallback', () => {
  for(const keepLegacyEdit of [false,true]) {
    const root=mappedFixture('piecewise-'+keepLegacyEdit);
    const path=join(root,'plan/cue-sheet.json');
    const sheet=JSON.parse(readFileSync(path,'utf8'));
    sheet.edl[0].actualCaptureWindow={piecewise_time_map:[{output_frame:0,source_seconds:2},{output_frame:30,source_seconds:3}]};
    if(!keepLegacyEdit) sheet.edl[0].edit=null;
    write(path,sheet);
    const r=run(root);
    assert.equal(r.code,1,r.out);
    assert.match(r.report.errors.join('\n'),/piecewise picture clock is not supported/);
    assert.equal(r.report.windows.length,0,'must not judge unseen source events using heuristic beat windows');
  }
});

test('mapped cue sheet: one clip split into two beats, the reversal is attributed to the right beat', () => {
  const root = mappedFixture('mapped');
  const r = run(root);
  assert.equal(r.code, 1, r.out);
  assert.equal(r.report.mode, 'mapped');
  assert.equal(r.report.inputs.cueSheet.path, 'plan/cue-sheet.json');
  const [b1, b2] = r.report.windows;
  assert.equal(b1.beat, 'B1'); assert.equal(b2.beat, 'B2');
  assert.equal(b1.clip, 'C1');
  assert.equal(b1.reversals, 0); assert.equal(b1.namedApproaches, 1);
  assert.equal(b2.reversals, 2); assert.equal(b2.namedApproaches, 1);
  assert.deepEqual(r.report.errors.filter((e) => /^B1/.test(e)), []);
  assert.ok(r.report.errors.some((e) => /^B2: pointer reverses direction 2 time\(s\)/.test(e)), r.report.errors.join('\n'));
});

test('mapped cue sheet: footage trimmed off the head is not judged, a plan-mode read of the same clip is', () => {
  const scrollEarly = (t) => { t.goto().wheel(20).wheel(-20); t.t += 0.3; };
  // trimStart 2.6: the early scroll (clip time 0.5-2.2 s) never reaches the program; the first approach (clip 2.9 s) does.
  const trimmed = mappedFixture('mapped-trimmed', { trimStart: 2.6, early: scrollEarly });
  const a = run(trimmed);
  const b1 = a.report.windows[0];
  assert.equal(b1.scrollReversals, 0, JSON.stringify(b1.findings));
  assert.equal(b1.scrollReturns, 0);
  // Same receipt with no cue sheet: one window for the whole clip, the early scroll counts.
  const planRoot = join(scratch, 'mapped-trimmed-plan');
  write(join(planRoot, 'capture', 'receipt.json'), readFileSync(join(trimmed, 'capture', 'receipt.json'), 'utf8'));
  const p = run(planRoot);
  assert.equal(p.report.mode, 'clip');
  assert.equal(p.report.windows.length, 1);
  assert.equal(p.report.windows[0].scrollReversals, 1);
  assert.equal(p.report.windows[0].scrollReturns, 1);
  assert.deepEqual(p.report.windows[0].segments, ['B1', 'B2']);
});

test('plan-mode cue sheet is judged per clip, like no sheet', () => {
  const t = new Take().approach({ x: 900, y: 500 }).click('go');
  const cueSheet = { generator: 'media-studio/build-cue-sheet', mode: 'plan', edl: null, beats: [{ beat: 'C1', slot_start: 0, slot_end: 9, screen: { clip: 'C1', kind: 'screen' }, actions: [] }] };
  const r = run(job('plan-sheet', { clips: { C1: clipRec(t) }, cueSheet }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.mode, 'clip');
  assert.equal(r.report.windows.length, 1);
  assert.equal(r.report.inputs.cueSheet.path, 'plan/cue-sheet.json');
});

test('mapped mode refuses a clip whose clock the receipt cannot state', () => {
  const root = mappedFixture('mapped-no-clock');
  const receipt = JSON.parse(readFileSync(join(root, 'capture', 'receipt.json'), 'utf8'));
  delete receipt.clips.C1.recastHeadTrimSeconds;
  write(join(root, 'capture', 'receipt.json'), receipt);
  const r = run(root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /C1: .*recastHeadTrimSeconds/);
});

test('native select names its real approach without claiming a click', () => {
  const t = new Take().approach({ x: 900, y: 500 });
  t.events.push({ type: 'select', method: 'locator.selectOption', t: t.t, tStart: t.t, x: 900, y: 500, label: 'Reviewer', target: 'persona select' });
  const r = run(job('native-select', { clips: { C1: clipRec(t) } }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.windows[0].namedApproaches, 1);
  assert.equal(r.report.windows[0].unnamedMoves, 0);
  assert.ok(r.report.windows[0].travelRatio <= 1.05);
  assert.equal(t.events.some(e => e.type === 'click'), false);
});
