// Screen stage plan and motion: pure logic, no browser, no ffmpeg. Run: node --test tests/screen-stage-plan.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const kit = pathToFileURL(join(pkg, 'kit', 'screencast')).href;
const M = await import(`${kit}/stage-math.mjs`);
const P = await import(`${kit}/stage-plan.mjs`);

const frame = { width: 1920, height: 1080, fps: 60 };
const viewport = { width: 1280, height: 720 };
const g = M.stageGeometry(frame, viewport);
const css = (x, y, w, h) => ({ x, y, w, h });
const slot = (over = {}) => ({ clipId: 'S01', startSeconds: 0, durationSeconds: 8, edit: { trimStart: 0, trimEnd: 8, speed: 1, skip: [], headHold: 0, srcSeconds: 8 }, ...over });
const clipOf = (actions, expectations = []) => ({ actions, expectations, frames: { times: [0, 1, 2], files: ['a.jpg', 'b.jpg', 'c.jpg'] } });
const click = (t, x, y, box, label) => ({ type: 'click', t: t + 0.06, tStart: t, x, y, label, targetBox: box });
const plan = (actions, expectations, slots = [slot()]) => P.buildStagePlan({ frame, viewport, slots, clips: { S01: clipOf(actions, expectations) } });

test('geometry: 1280x720 at 1920x1080 is 1.5 film px per CSS px and a non-16:9 viewport is refused', () => {
  assert.equal(g.k, 1.5);
  assert.throws(() => M.stageGeometry(frame, { width: 1280, height: 860 }), /full bleed has no bars/);
});

test('spring: critically damped, no overshoot, peak speed 0.1 s, ~90% by 0.37 s, settled by 0.63 s', () => {
  const at = (tau) => M.springAxis(0, 0, 1, tau);
  let prev = 0, peakAt = 0, peak = 0;
  for (let i = 1; i <= 120; i++) {
    const tau = i / 100, s = at(tau);
    assert.ok(s.x <= 1 + 1e-9 && s.x >= prev - 1e-9, 'monotone, never past the target');
    if (s.v > peak) { peak = s.v; peakAt = tau; }
    prev = s.x;
  }
  assert.ok(peakAt >= 0.08 && peakAt <= 0.15, `peak speed at ${peakAt}`);
  assert.ok(at(0.35).x >= 0.88 && at(0.35).x <= 0.93, `0.35 s: ${at(0.35).x}`);
  assert.ok(at(0.6).x >= 0.985, `0.6 s: ${at(0.6).x}`);
  assert.equal(at(0).x, 0);
});

test('zoom: 1.5 by default, 1.8 only with a tiny target and a tiny result in view, never outside 1.3-1.8, a huge region stays on the full page', () => {
  const small = M.zoomForBox(M.toStageBox(g, css(100, 100, 80, 30)), g);
  const medium = M.zoomForBox(M.toStageBox(g, css(100, 100, 560, 200)), g);
  const huge = M.zoomForBox(M.toStageBox(g, css(0, 0, 1000, 600)), g);
  assert.equal(small, 1.8, 'a tiny region may reach 1.8');
  assert.ok(medium >= 1.3 && medium <= 1.5, `medium ${medium}`);
  assert.equal(huge, 1);
  // a lone tiny control with no result stays at the 1.5 default
  const lone = plan([click(1.5, 300, 200, css(260, 185, 80, 30), 'Lone')]);
  assert.equal(lone.camera.segments[0].to.z, 1.5);
  // the same control with a tiny result beside it may go to 1.8
  const pair = plan([click(1.5, 300, 200, css(260, 185, 80, 30), 'Small')], [{ label: 'Small result', observed: true, observedAt: 1.8, at: 1.8, targetBox: css(350, 185, 60, 30) }]);
  assert.equal(pair.camera.segments[0].to.z, 1.8);
});

test('clamp: the view never leaves the page, whatever the target', () => {
  for (const [x, y] of [[0, 0], [1900, 1060], [1900, 5], [5, 1070]]) {
    const cam = M.cameraForBox({ x: x - 20, y: y - 10, w: 40, h: 20 }, g, { bias: true });
    const v = M.viewRect(cam, g);
    assert.ok(v.x >= -1e-6 && v.y >= -1e-6 && v.x + v.w <= g.W + 1e-6 && v.y + v.h <= g.H + 1e-6, JSON.stringify(v));
  }
});

test('camera track: opens on the full page, lands before the click, holds still, closes on the full page, same framing as the start', () => {
  const p = plan([
    { type: 'move', t: 0.8, x: 300, y: 200, cursor: 'default' },
    click(1.6, 300, 200, css(260, 185, 80, 30), 'Open'),
    click(3.4, 900, 500, css(860, 485, 80, 30), 'Apply'),
  ], [{ label: 'Done', observed: true, at: 3.5, observedAt: 3.6, targetBox: css(840, 520, 200, 60) }], [slot({ durationSeconds: 7, edit: { trimStart: 0, trimEnd: 7, speed: 1, skip: [], headHold: 0, srcSeconds: 7 } })]);
  assert.deepEqual(M.cameraAt(p.camera, 0.2, g), { ...M.wideCamera(g), vx: 0, vy: 0, vz: 0 });
  const first = M.cameraAt(p.camera, 1.6, g);
  assert.ok(first.z >= 1.3, `zoomed at the first press: ${first.z}`);
  assert.ok(p.planned.every((a) => a.inView), 'every target inside the view at its press');
  // a hold: no motion between settle and the next start
  const a = M.cameraAt(p.camera, 2.2, g), b = M.cameraAt(p.camera, 2.6, g);
  assert.ok(Math.hypot(a.cx - b.cx, a.cy - b.cy, (a.z - b.z) * 100) < 1, 'camera still during the hold');
  const end = M.cameraAt(p.camera, 6.95, g);
  assert.ok(Math.abs(end.z - 1) < 0.01 && Math.abs(end.cx - g.W / 2) < 1 && Math.abs(end.cy - g.H / 2) < 1, JSON.stringify(end));
  const first0 = M.cameraAt(p.camera, 0, g);
  assert.equal(end.z > 0.99, true);
  assert.ok(Math.abs(first0.z - end.z) < 0.01);
});

test('grouping: presses close together with a fitting joint box share one region and one camera move', () => {
  const p = plan([
    click(1.5, 300, 200, css(260, 185, 80, 30), 'A'),
    click(2.3, 420, 230, css(380, 215, 80, 30), 'B'),
    click(5.5, 900, 520, css(860, 505, 80, 30), 'C'),
  ]);
  assert.equal(p.regions.length, 2);
  assert.deepEqual(p.regions[0].labels, ['A', 'B']);
  const regionMoves = p.moves.filter((m) => m.reason === 'open' || m.reason === 'region');
  assert.equal(regionMoves.length, 2);
});

test('merge: a later target already comfortably inside the held view needs no new move', () => {
  const p = plan([
    click(1.5, 600, 340, css(560, 320, 80, 30), 'A'),
    click(3.5, 640, 350, css(600, 335, 80, 30), 'B'),
  ]);
  const regions = p.moves.filter((m) => m.reason === 'open' || m.reason === 'region');
  assert.equal(regions.length, 1, JSON.stringify(p.moves));
  assert.equal(p.regions[1].merged, true);
});

test('pan, not zoom out: two far targets pan at the same zoom with no pull back between them', () => {
  const p = plan([
    click(1.5, 200, 150, css(160, 135, 80, 30), 'Left'),
    click(3.2, 1100, 560, css(1060, 545, 80, 30), 'Right'),
  ]);
  const mid = M.cameraAt(p.camera, 2.6, g);
  assert.ok(mid.z >= 1.45, `still zoomed between the targets: ${mid.z}`);
  assert.deepEqual(p.moves.map((m) => m.reason), ['open', 'region', 'close']);
});

test('context: a long quiet gap pulls back to the full page and the next target zooms in again', () => {
  const p = plan([
    click(1.5, 200, 150, css(160, 135, 80, 30), 'Left'),
    click(7.2, 1100, 560, css(1060, 545, 80, 30), 'Right'),
  ], [], [slot({ durationSeconds: 10, edit: { trimStart: 0, trimEnd: 10, speed: 1, skip: [], headHold: 0, srcSeconds: 10 } })]);
  assert.deepEqual(p.moves.map((m) => m.reason), ['open', 'context', 'region', 'close']);
});

test('typing is a zoom target: the field stays framed until the typing ends', () => {
  const p = plan([
    click(1.4, 500, 300, css(400, 285, 300, 32), 'Name'),
    { type: 'type', t: 3.1, tStart: 1.9, tEnd: 3.0, chars: 18, label: 'Name' },
  ]);
  assert.equal(p.planned.length, 1);
  assert.ok(p.planned[0].tEnd >= 3.0, `target held until ${p.planned[0].tEnd}`);
  const close = p.moves.find((m) => m.reason === 'close');
  assert.ok(close.t0 >= 3.0 + 0.9 - 0.01, `pull back at ${close.t0}`);
});

test('cursor: passes exactly through every recorded sample, never overshoots, hidden before the first one, and is on the click point at the click time', () => {
  const p = plan([
    { type: 'move', t: 1.0, x: 100, y: 100, cursor: 'default' },
    { type: 'move', t: 1.1, x: 180, y: 130, cursor: 'default' },
    { type: 'move', t: 1.25, x: 300, y: 200, cursor: 'pointer' },
    click(1.9, 300, 200, css(260, 185, 80, 30), 'Open'),
  ]);
  const tr = M.buildCursorTrack(p.cursor.samples);
  for (const s of p.cursor.samples) { const c = M.cursorAt(tr, s.t); assert.ok(Math.hypot(c.x - s.x, c.y - s.y) < 1e-6); }
  const hidden = M.cursorAt(tr, 0.5);
  assert.equal(hidden.visible, 0);
  const onClick = M.cursorAt(tr, p.cursor.clicks[0].t);
  assert.ok(Math.hypot(onClick.x - p.cursor.clicks[0].x, onClick.y - p.cursor.clicks[0].y) < 1e-6);
  for (let t = 1.0; t <= 1.9; t += 0.01) { const c = M.cursorAt(tr, t); assert.ok(c.x >= 150 - 1e-6 && c.x <= 450 + 1e-6 && c.y >= 150 - 1e-6 && c.y <= 300 + 1e-6, `${t} ${c.x},${c.y}`); }
  assert.equal(M.cursorAt(tr, 1.5).kind, 'hand');
  assert.equal(M.cursorKind('text'), 'ibeam');
  assert.equal(M.cursorKind('default'), 'arrow');
});

test('cursor size: 40 px on the full page, 58 px at the largest zoom; press squash dips and recovers', () => {
  assert.equal(M.cursorHeightFor(1), 40);
  assert.equal(Math.round(M.cursorHeightFor(1.8)), 58);
  const clicks = [{ t: 2 }];
  assert.equal(M.pressScale(clicks, 1.9), 1);
  assert.ok(M.pressScale(clicks, 2.055) <= 0.905 && M.pressScale(clicks, 2.055) >= 0.89, 'the press response dips to about 0.9');
  assert.equal(M.pressScale(clicks, 2.3), 1);
});

test('edit map: headHold, speed and skip move events onto film time; a press inside a skip has no film time', () => {
  const edit = { trimStart: 0, trimEnd: 10, speed: 1, skip: [[3, 5]], headHold: 0.5, srcSeconds: 10 };
  const p = plan([click(2, 300, 200, css(260, 185, 80, 30), 'Early'), click(4, 300, 200, css(260, 185, 80, 30), 'Dropped'), click(6, 300, 200, css(260, 185, 80, 30), 'Late')], [], [slot({ edit })]);
  assert.deepEqual(p.planned.map((a) => a.label), ['Early', 'Late']);
  assert.equal(p.planned[0].t, 2.5);
  assert.equal(p.planned[1].t, 6 - 2 + 0.5);
  assert.equal(M.slotToSource(edit, 0.2), 0, 'frozen on the first frame during headHold');
  assert.equal(M.slotToSource(edit, 2.5), 2);
  assert.equal(M.slotToSource(edit, 4.5), 6, 'jumps over the skip');
});

test('continuity: adjacent slots of different clips share one camera, with no reset at the boundary', () => {
  const clips = { A: clipOf([click(1.5, 300, 200, css(260, 185, 80, 30), 'One')]), B: clipOf([click(0.4, 330, 210, css(290, 195, 80, 30), 'Two')]) };
  clips.B.frames = clips.A.frames;
  const slots = [slot({ clipId: 'A', startSeconds: 0, durationSeconds: 4, edit: { trimStart: 0, trimEnd: 4, speed: 1, skip: [], headHold: 0, srcSeconds: 4 } }), slot({ clipId: 'B', startSeconds: 4, durationSeconds: 5, edit: { trimStart: 0, trimEnd: 5, speed: 1, skip: [], headHold: 0, srcSeconds: 5 } })];
  const p = P.buildStagePlan({ frame, viewport, slots, clips });
  const before = M.cameraAt(p.camera, 3.99, g), after = M.cameraAt(p.camera, 4.01, g);
  assert.ok(Math.abs(before.z - after.z) < 0.02 && before.z > 1.3, `zoom ${before.z} -> ${after.z}`);
  assert.deepEqual(p.planned.map((a) => a.label), ['One', 'Two']);
  assert.equal(p.planned[1].t, 4.4);
  assert.equal(p.moves.filter((m) => m.reason === 'close').length, 1);
});

test('frame lookup: the last frame at or before the source time; frames only arrive on change', () => {
  const times = [0, 0.4, 1.9];
  assert.equal(M.frameIndexAt(times, 0), 0);
  assert.equal(M.frameIndexAt(times, 1.0), 1);
  assert.equal(M.frameIndexAt(times, 1.9), 2);
  assert.equal(M.frameIndexAt(times, 50), 2);
});

test('determinism: the same input gives byte-identical plans', () => {
  const run = () => JSON.stringify(plan([click(1.6, 300, 200, css(260, 185, 80, 30), 'Open')]));
  assert.equal(run(), run());
});

test('a press with no recorded target box is framed from its point and flagged', () => {
  const p = plan([{ type: 'click', t: 1.66, tStart: 1.6, x: 300, y: 200, label: 'Old' }]);
  assert.equal(p.planned[0].estimated, true);
  assert.ok(p.warnings.some((w) => /no recorded target box/.test(w)));
});

test('idle: only time with no input and no new frame is idle; compression of anything else needs a declared reason', () => {
  const idle = P.idleRanges({ actions: [{ t: 1 }, { type: 'click', t: 5.1, tStart: 5 }], frameTimes: [0, 0.5, 1, 1.2, 5, 5.2, 5.3], clipSeconds: 6 });
  assert.deepEqual(idle, [[1.2, 5]]);
  assert.equal(P.compressionProblems({ edit: { skip: [[2, 4]], speed: 1 }, idle, label: 'S01' }).length, 0);
  assert.equal(P.compressionProblems({ edit: { skip: [[0, 2]], speed: 1 }, idle, label: 'S01' }).length, 1);
  assert.equal(P.compressionProblems({ edit: { skip: [[0, 2]], speed: 1 }, idle, speedReason: 'a bounded real wait', label: 'S01' }).length, 0);
  assert.equal(P.compressionProblems({ edit: { skip: [], speed: 4 }, idle, label: 'S01' }).length, 1);
});

test('camera leads the pointer: it starts 0.1 s before the first move of the approach, so the two are not at peak together', () => {
  const p = plan([
    { type: 'move', t: 0.9, x: 100, y: 100, cursor: 'default' }, { type: 'move', t: 1.1, x: 220, y: 150, cursor: 'default' },
    click(1.5, 300, 200, css(260, 185, 80, 30), 'Go'),
  ]);
  const open = p.camera.segments.find((s) => s.reason === 'open');
  assert.ok(open.t0 < 0.9 - 0.1 + 1e-6, `camera starts ${open.t0}, before the pointer starts at 0.9`);
  assert.ok(open.t0 >= 0.5 && open.t0 <= 0.6 + 1e-6, 'the film opens on a clean full page held 0.5-0.6 s, however late the pointer starts');
  const late = plan([{ type: 'move', t: 2.0, x: 100, y: 100, cursor: 'default' }, { type: 'move', t: 2.2, x: 220, y: 150, cursor: 'default' }, click(2.6, 300, 200, css(260, 185, 80, 30), 'Go')], [], [slot({ durationSeconds: 8 })]);
  assert.ok(late.camera.segments[0].t0 <= 0.6 + 1e-6, 'a late pointer does not lengthen the opening hold');
  const tight = plan([{ type: 'move', t: 0.6, x: 100, y: 100, cursor: 'default' }, click(1.5, 300, 200, css(260, 185, 80, 30), 'Go')]);
  assert.equal(tight.camera.segments[0].t0, 0.5);
});

test('a result elsewhere on the page is reached within 0.25 s of the press and is in the planned view', () => {
  const changes = [{ t: 1.5, boxes: [css(900, 520, 280, 120)] }];
  const clip = { ...clipOf([click(1.5, 300, 200, css(260, 185, 80, 30), 'Export')]), changes };
  const p = P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: clip } });
  const res = p.camera.segments.find((s) => s.reason === 'result');
  assert.ok(res, 'a result segment exists');
  assert.ok(res.t0 - 1.5 <= 0.25 + 1e-6 && res.t0 >= 1.5, `result move starts ${res.t0 - 1.5} s after the press`);
  const box = M.toStageBox(g, css(900, 520, 280, 120));
  assert.ok(M.boxInView({ ...res.to }, g, box), 'the result is inside the view the camera settles on');
  assert.equal(p.results.length, 1);
});

const C = await import(`${kit}/stage-checks.mjs`);

test('plan checks pass a core-v2 plan and fail core-v1 style plans (zoom, lead, result, opening hold)', () => {
  const actions = [
    { type: 'move', t: 0.9, x: 100, y: 100, cursor: 'default' }, { type: 'move', t: 1.1, x: 220, y: 150, cursor: 'default' },
    click(1.5, 300, 200, css(260, 185, 80, 30), 'Go'),
  ];
  const changes = [{ t: 1.5, boxes: [css(900, 520, 280, 120)] }];
  const good = P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: { ...clipOf(actions), changes } } });
  assert.deepEqual(C.planProblems(good), []);
  const v1 = JSON.parse(JSON.stringify(good));
  v1.camera.segments[0].t0 = 1.0;                       // camera starts after the pointer, not before it
  v1.regions[0].zoom = 1.8;                             // lone control at the 1.8 ceiling
  v1.camera.segments = v1.camera.segments.filter((s) => s.reason !== 'result'); // result never reached
  const problems = C.planProblems(v1).join(' | ');
  assert.match(problems, /zoomed 1\.8x/);
  assert.match(problems, /must lead by about 0\.1 s/);
  assert.match(problems, /no camera move within 0\.25 s/);
  const early = JSON.parse(JSON.stringify(good)); early.camera.segments[0].t0 = 0.1;
  assert.match(C.planProblems(early).join(' | '), /clean full page for at least 0\.35 s/);
});

const F = await import(`${kit}/stage-film-checks.mjs`);

test('film checks: a coil of discrete copies has repeated structure along the motion that a true blur does not', () => {
  const w = 320, h = 64;
  let seed = 7; const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
  const stripes = new Float32Array(w); for (let x = 0; x < w;) { const run = 3 + Math.floor(rnd() * 8), v = rnd() > 0.5 ? 235 : 40; for (let i = 0; i < run && x < w; i++) stripes[x++] = v; }
  const at = (x) => { const x0 = Math.floor(x), f = x - x0, a = stripes[Math.max(0, Math.min(w - 1, x0))], b = stripes[Math.max(0, Math.min(w - 1, x0 + 1))]; return a * (1 - f) + b * f; };
  const shifted = (copies, span) => { const out = new Float32Array(w * h); for (let x = 0; x < w; x++) { let s = 0; for (let k = 0; k < copies; k++) s += at(x - (k / (copies - 1)) * span); for (let y = 0; y < h; y++) out[y * w + x] = s / copies; } return out; };
  const ideal = shifted(145, 36), blurAgain = shifted(97, 36), coil = shifted(6, 36);
  const good = F.ghostExcess(blurAgain, ideal, w, h, { x: 1, y: 0 }, 48);
  const bad = F.ghostExcess(coil, ideal, w, h, { x: 1, y: 0 }, 48);
  assert.ok(good.excess < 0.06, `a second sampling of the same blur: ${good.excess}`);
  assert.ok(bad.excess > 0.15, `six copies spaced ${36 / 5} px: ${bad.excess} at lag ${bad.lag}`);
});

test('film checks: colour shift is the median patch difference, still runs and capture rate', () => {
  assert.ok(F.colourShift([[250, 250, 250], [250, 251, 250], [249, 250, 250]], [[251, 251, 251], [251, 251, 251], [251, 251, 251]]) <= 1.01);
  assert.ok(F.colourShift([[240, 244, 250], [240, 244, 250], [240, 244, 250]], [[251, 251, 251], [251, 251, 251], [251, 251, 251]]) >= 10, 'a cast of 11 levels is caught');
  assert.equal(F.colourShift([null, null, [1, 1, 1]], [[1, 1, 1], [1, 1, 1], [1, 1, 1]]), null);
  const a = new Uint8Array(100).fill(10), b = new Uint8Array(100).fill(10), c = new Uint8Array(100).fill(10); c.fill(200, 0, 40);
  assert.deepEqual(F.stillRuns([a, b, a, c, c]), [{ from: 0, to: 2 }, { from: 3, to: 4 }]);
  const t = []; for (let i = 0; i < 30; i++) t.push(i / 60);
  const r60 = F.captureRate(t), r37 = F.captureRate(t.map((v) => v * (60 / 37)));
  assert.ok(r60.uniqueFps > 55 && r37.uniqueFps < 40);
});

const SL = await import(`${kit}/sync-lib.mjs`);
const CHG = await import(`${kit}/stage-changes.mjs`);

test('time map: typing at 2x is a linear speed ramp in and out, inverts exactly, and moves every later event', () => {
  const edit = { trimStart: 0, trimEnd: 10, speed: 1, skip: [], headHold: 0, srcSeconds: 10, ramps: [{ from: 2, to: 5, speed: 2, ramp: 0.15 }] };
  const len = SL.slotLen(edit, 2, 5);
  assert.ok(len > 1.5 && len < 1.7, `span plays in ${len} s`);
  assert.ok(Math.abs(SL.slotLen(edit, 0, 2) - 2) < 1e-9, 'real speed before the span');
  assert.ok(Math.abs(SL.slotLen(edit, 5, 10) - 5) < 1e-9, 'real speed after the span');
  assert.ok(Math.abs(SL.editSlotSeconds(edit) - (2 + len + 5)) < 1e-9);
  for (const ts of [0.5, 2.05, 2.3, 3.5, 4.9, 5.1, 8]) {
    const slotT = SL.clipToSlot(edit, ts);
    assert.ok(Math.abs(M.slotToSource(edit, slotT) - ts) < 1e-3, `${ts} -> ${slotT} -> ${M.slotToSource(edit, slotT)}`);
  }
  const plain = { trimStart: 1, trimEnd: 9, speed: 2, skip: [[3, 4]], headHold: 0.5, srcSeconds: 10 };
  assert.equal(SL.clipToSlot(plain, 6), 0.5 + (2 + 2) / 2);
  assert.equal(M.slotToSource(plain, 2.5), 6);
  assert.throws(() => SL.ratePieces({ ramps: [{ from: 1, to: 3, speed: 2 }, { from: 2, to: 4, speed: 2 }] }), /overlap/);
  assert.deepEqual(SL.ratePieces({ ramps: [{ from: 1, to: 1.2, speed: 2 }] }), []);
});

test('typing spans: stop 0.4 s before the end of the typing, and at the first change outside the field', () => {
  const times = [0, 1, 1.5, 2.5, 3.5, 4.5], files = times.map((_, i) => `f${i}`);
  const blank = new Uint8Array(320 * 180).fill(240);
  const withMenu = blank.slice(); for (let y = 90; y < 150; y++) for (let x = 200; x < 300; x++) withMenu[y * 320 + x] = 30;
  const grid = (f) => (f === 'f3' || f === 'f4' || f === 'f5' ? withMenu : blank);
  const field = { x: 100, y: 100, w: 300, h: 40 };
  const quiet = CHG.typingSpans({ actions: [{ type: 'type', tStart: 1, tEnd: 3, targetBox: field }], frames: { times: [0, 1, 2], files: ['f0', 'f1', 'f2'] }, viewport, grid });
  assert.deepEqual(quiet, [{ from: 1, to: 2.6, speed: 2, reason: 'typing' }]);
  const popup = CHG.typingSpans({ actions: [{ type: 'type', tStart: 1, tEnd: 4.5, targetBox: field }], frames: { times, files }, viewport, grid });
  assert.ok(popup.length === 1 && popup[0].to < 2.7 && popup[0].to > 2.0, JSON.stringify(popup));
  assert.deepEqual(CHG.typingSpans({ actions: [{ type: 'type', tStart: 1, tEnd: 1.6, targetBox: field }], frames: { times, files }, viewport, grid }), [], 'a short burst plays at real speed');
  assert.equal(CHG.typingSpans({ actions: [{ type: 'type', tStart: 1, tEnd: 3, targetBox: field }], frames: { times, files }, viewport, speed: 5, grid })[0].speed, 3, 'capped at 3x');
});

test('zoom modes: off keeps the full page, manual follows the declared regions (instant is a declared cut), level moves the default', () => {
  const acts = [click(1.5, 300, 200, css(260, 185, 80, 30), 'Go'), click(4.5, 900, 500, css(860, 485, 80, 30), 'Later')];
  const mk = (zoom, extra = {}) => P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: clipOf(acts) }, options: { zoom, ...extra } });
  assert.deepEqual(mk({ mode: 'off' }).camera.segments, []);
  assert.equal(mk({ level: 1.3 }).camera.segments[0].to.z, 1.3);
  const manual = mk({ mode: 'manual', regions: [{ target: 'Go', from: 1.0, to: 3.0, level: 1.7 }, { target: 'Later', from: 4.0, to: 6.0, level: 1.4, instant: true }] });
  const open = manual.camera.segments[0];
  assert.equal(open.to.z, 1.7); assert.equal(open.t0, 1.0); assert.equal(open.declared, true);
  const cut = manual.camera.segments.find((s) => s.reason === 'cut');
  assert.equal(cut.instant, true); assert.equal(cut.t0, 4.0);
  assert.equal(M.cameraAt(manual.camera, 4.0, g).z, 1.4, 'a declared cut lands the same frame');
  assert.deepEqual(C.zoomProblems(manual), [], 'declared zoom is the author\'s choice');
  assert.throws(() => mk({ mode: 'manual', regions: [{ target: 'Nope' }] }), /no recorded action labelled "Nope"/);
});

test('highlight: the recorded element box, eased in and out, one at a time', () => {
  const acts = [click(1.5, 300, 200, css(260, 185, 80, 30), 'Go'), click(4.5, 900, 500, css(860, 485, 80, 30), 'Later')];
  const p = P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: clipOf(acts) }, options: { highlights: [{ action: 'Go', start: -0.2, hold: 1.5 }] } });
  assert.equal(p.highlights.length, 1);
  const h = p.highlights[0];
  assert.equal(h.t0, 1.3); assert.equal(h.t1, 2.8); assert.equal(h.dim, 0.45);
  const cssBox = css(260, 185, 80, 30);
  assert.ok(h.box.x <= cssBox.x * 1.5 && h.box.y <= cssBox.y * 1.5 && h.box.x + h.box.w >= (cssBox.x + cssBox.w) * 1.5, 'the cutout holds the recorded box');
  assert.equal(M.stateAt(p, 1.2).highlight, null);
  assert.equal(M.stateAt(p, 1.3).highlight.amount, 0);
  assert.ok(M.stateAt(p, 1.425).highlight.amount > 0.4 && M.stateAt(p, 1.425).highlight.amount < 0.6);
  assert.equal(M.stateAt(p, 2.0).highlight.amount, 1);
  assert.equal(M.stateAt(p, 3.0).highlight, null, 'gone after the hold');
  assert.throws(() => P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: clipOf(acts) }, options: { highlights: [{ action: 'Go', hold: 3.5 }, { action: 'Later', start: -1 }] } }), /overlap/);
  assert.throws(() => P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: clipOf([{ type: 'click', t: 1.5, tStart: 1.5, x: 300, y: 200, label: 'Blind' }]) }, options: { highlights: [{ action: 'Blind' }] } }), /no recorded element box/);
});

test('phone screen inside a 16:9 frame: centred at 0.9 of the height over a generated gradient; any other aspect mismatch is refused', () => {
  const phone = { width: 405, height: 720 };
  assert.throws(() => M.stageGeometry(frame, phone), /full bleed has no bars/);
  const pg = M.stageGeometry(frame, phone, { layout: 'phone' });
  assert.ok(Math.abs(pg.placement.h - 0.9 * 1080) < 1e-6 && Math.abs(pg.placement.x + pg.placement.w / 2 - 960) < 1e-6 && Math.abs(pg.placement.y + pg.placement.h / 2 - 540) < 1e-6);
  assert.throws(() => M.stageGeometry({ width: 1080, height: 1920, fps: 60 }, { width: 1280, height: 720 }, { layout: 'phone' }), /full bleed/, 'a landscape capture is never placed in a portrait frame');
  const clip = clipOf([{ type: 'tap', t: 1.56, tStart: 1.5, x: 200, y: 360, label: 'Tap', targetBox: css(150, 340, 100, 40) }]);
  const p = P.buildStagePlan({ frame, viewport: phone, slots: [slot()], clips: { S01: { ...clip, touch: true } }, options: { layout: 'phone', background: { colors: [[10, 20, 30], [60, 80, 120]] } } });
  assert.equal(p.cursor.mode, 'touch');
  assert.deepEqual(p.cursor.clicks[0].x, Math.round((200 * pg.k + pg.ox) * 1000) / 1000, 'the tap point is where the stage draws the page');
  assert.deepEqual(p.background.colors, [[10, 20, 30], [60, 80, 120]]);
  const [dark, light] = M.gradientFromColour([240, 238, 230]);
  assert.ok(dark.every((v) => v < 90) && light.every((v) => v < 160), 'both gradient tones stay dark enough for a screen to stand out');
  assert.equal(P.buildStagePlan({ frame, viewport, slots: [slot()], clips: { S01: clipOf([]) } }).background, null, 'full bleed has no background');
  const portrait = M.stageGeometry({ width: 1080, height: 1920, fps: 60 }, phone);
  assert.ok(Math.abs(portrait.k - 1080 / 405) < 1e-9 && portrait.zoom.default === 1.25);
});
