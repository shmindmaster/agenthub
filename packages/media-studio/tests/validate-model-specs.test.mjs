// Model-written layers gate and resolver: every generated item is anchored to the cue sheet, sits inside its beat, never
// covers the pointer, the active element or the next click target, and leaves the source recording and audio untouched.
// Synthetic JSON fixtures in tests/fixtures/model-specs, no provider call, no ffmpeg. Run: node --test tests/validate-model-specs.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const gate = join(pkg, 'scripts', 'validate-model-specs.mjs');
const resolver = join(pkg, 'scripts', 'model-specs-resolve.mjs');
const fixtures = join(pkg, 'tests', 'fixtures', 'model-specs');
const scratch = mkdtempSync(join(tmpdir(), 'model-specs-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const read = (p) => JSON.parse(readFileSync(p, 'utf8'));
const write = (p, data) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2)); };
const LAYERS = ['moments', 'overlays', 'captions', 'diagram'];

/** A job from the fixtures: synthetic recording and audio bytes, receipt and aligner reports bound to them, layers bound to the cue sheet. */
function job(name, edit = {}) {
  const root = join(scratch, name);
  write(join(root, 'job.json'), { kind: 'product-screencast', deliveryProfile: 'briefing-board' });
  const sheet = read(join(fixtures, 'cue-sheet.json'));
  const receipt = read(join(fixtures, 'receipt.json'));
  const layers = Object.fromEntries(LAYERS.map((l) => [l, read(join(fixtures, `${l}.json`))]));
  edit.sheet?.(sheet); edit.receipt?.(receipt); edit.layers?.(layers);
  for (const [id, rec] of Object.entries(receipt.clips)) {
    write(join(root, 'capture', rec.file), `synthetic recording ${id}`);
    rec.sha256 = sha(join(root, 'capture', rec.file));
  }
  for (const id of ['S01', 'S02']) {
    write(join(root, 'voice', 'takes', `${id}.wav`), `synthetic narration ${id}`);
    write(join(root, 'voice', 'align', `${id}.json`), { method: 'forced-alignment', take: { path: `voice/takes/${id}.wav`, sha256: sha(join(root, 'voice', 'takes', `${id}.wav`)) }, words: [] });
  }
  write(join(root, 'plan', 'cue-sheet.json'), sheet);
  write(join(root, 'capture', 'receipt.json'), receipt);
  for (const l of LAYERS) {
    if (!layers[l]) continue;
    layers[l].inputs.cueSheet.sha256 = sha(join(root, 'plan', 'cue-sheet.json'));
    write(join(root, 'plan', 'model-specs', `${l}.json`), layers[l]);
  }
  edit.after?.(root);
  return root;
}
const run = (root, args = []) => {
  const r = spawnSync(process.execPath, [gate, root, ...args], { encoding: 'utf8', windowsHide: true });
  const path = join(root, 'qa', 'model-specs-report.json');
  return { code: r.status, out: `${r.stdout}${r.stderr}`, report: existsSync(path) ? read(path) : null };
};
const overlay = (over) => ({ kind: 'callout', beatId: 'S01', anchor: 'action', actionLabel: 'Open queue', fromWord: 0, toWord: 0, region: 'top-left', text: 'Opens the queue', note: '', ...over });

test('clean job passes with every check performed, inputs bound and a density summary', () => {
  const root = job('clean');
  const { code, out, report } = run(root);
  assert.equal(code, 0, out);
  assert.equal(report.generator, 'media-studio/validate-model-specs');
  assert.equal(report.ok, true);
  assert.deepEqual(report.errors, []);
  for (const check of ['layer-files', 'anchors', 'timing', 'geometry', 'one-at-a-time', 'captions', 'sources']) assert.ok(report.checks.performed.includes(check), check);
  assert.equal(report.inputs.cueSheet.sha256, sha(join(root, 'plan', 'cue-sheet.json')));
  assert.equal(report.inputs['layer-overlays'].path, 'plan/model-specs/overlays.json');
  assert.equal(report.inputs.receipt.path, 'capture/receipt.json');
  assert.equal(report.frame.width, 1600);
  assert.ok(report.density.overlayShare > 0 && report.density.overlayShare < 1);
  assert.equal(report.density.fullscreenShare, 0);
  assert.equal(report.items.filter((i) => i.geometry === 'clear').length, 3);
});

test('an item whose anchor is not in the cue sheet fails', () => {
  const root = job('anchor-missing', { layers: (l) => { l.overlays.output.overlays[0].actionLabel = 'Export report'; l.moments.output.moments[0].beatId = 'S07'; } });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /Export report/.test(e) && /not a recorded action of S01/.test(e)), report.errors.join('\n'));
  assert.ok(report.errors.some((e) => /S07/.test(e)), report.errors.join('\n'));
});

test('an overlay over the pointer or the next click target fails', () => {
  const root = job('pointer', { layers: (l) => { l.overlays.output.overlays[0] = overlay({ beatId: 'S02', actionLabel: 'Approve', region: 'right-panel', text: 'Approve it' }); } });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /covers the pointer at Approve/.test(e)), report.errors.join('\n'));
  const next = job('next-target', { layers: (l) => { l.overlays.output.overlays[0] = overlay({ region: 'right-panel' }); } });
  const r = run(next);
  assert.equal(r.code, 1);
  assert.ok(r.report.errors.some((e) => /Approve/.test(e)), `right panel during the first click sits over the next click target: ${r.report.errors.join('\n')}`);
});

test('a resolved time outside the anchored beat fails', () => {
  const root = job('outside', { sheet: (s) => { s.beats[0].actions[0].action_time = 6.4; } });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /outside S01/.test(e)), report.errors.join('\n'));
});

test('caption words that do not match the transcript by index fail', () => {
  const root = job('caption-words', { layers: (l) => { l.captions.output.chunks[0].text = 'Open a queue and'; } });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /spoken words 0-3 of S01/.test(e)), report.errors.join('\n'));
  const overlapping = job('caption-overlap', { layers: (l) => { l.captions.output.chunks[1].fromWord = 3; l.captions.output.chunks[1].text = 'and pick the first request.'; } });
  assert.ok(run(overlapping).report.errors.some((e) => /more than once/.test(e)));
});

test('a source recording or audio that changed since capture fails', () => {
  const root = job('hash', { after: (r) => writeFileSync(join(r, 'capture', 'clips', 'C1.webm'), 'retimed recording') });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /C1/.test(e) && /recording/.test(e) && /receipt/.test(e)), report.errors.join('\n'));
  const audio = job('audio-hash', { after: (r) => writeFileSync(join(r, 'voice', 'takes', 'S02.wav'), 're-voiced') });
  const a = run(audio);
  assert.equal(a.code, 1);
  assert.ok(a.report.errors.some((e) => /S02/.test(e) && /audio/.test(e)), a.report.errors.join('\n'));
});

test('a receipt without geometry says so and never passes the check silently', () => {
  const root = job('no-geometry', { receipt: (r) => { for (const e of r.clips.C1.actions) { delete e.x; delete e.y; } r.clips.C1.expectations[0].targetBox = null; } });
  const { code, out, report } = run(root);
  assert.equal(code, 0, out);
  assert.ok(!report.checks.performed.includes('geometry'));
  const skipped = report.checks.notPerformed.filter((n) => n.check === 'geometry');
  assert.equal(skipped.length, 3);
  assert.ok(skipped.every((n) => n.reason === 'not checked: no geometry in receipt'));
  assert.ok(report.items.every((i) => i.layer === 'captions' || i.layer === 'moments' || i.geometry === 'not checked: no geometry in receipt'));
  assert.match(out, /not checked: no geometry in receipt/);
});

test('two explanatory overlays at once fail; a fullscreen insert over an action fails', () => {
  const root = job('two-at-once', { layers: (l) => { l.overlays.output.overlays.push(overlay({ kind: 'step', anchor: 'words', actionLabel: '', fromWord: 2, toWord: 3, region: 'bottom-left', text: 'Step one' })); } });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /one explanatory overlay at a time/.test(e)), report.errors.join('\n'));
  const full = job('fullscreen', { layers: (l) => { l.diagram.output.diagrams[0].placement = 'fullscreen'; } });
  const f = run(full);
  assert.equal(f.code, 1);
  assert.ok(f.report.errors.some((e) => /fullscreen/.test(e) && /Approve|pause/.test(e)), f.report.errors.join('\n'));
  assert.ok(f.report.density.fullscreenShare > 0);
});

test('a stale layer, a pending fallback or a job with no layers fails', () => {
  const stale = job('stale', { after: (r) => { const s = read(join(r, 'plan', 'cue-sheet.json')); s.beats[0].expected_ui_state = 'changed'; write(join(r, 'plan', 'cue-sheet.json'), s); } });
  assert.ok(run(stale).report.errors.some((e) => /stale/.test(e)));
  const pending = job('pending', { after: (r) => write(join(r, 'plan', 'model-specs', 'fallback-needed.json'), { entries: [{ layer: 'diagram', reason: 'refusal', detail: 'x' }] }) });
  const p = run(pending);
  assert.equal(p.code, 1);
  assert.ok(p.report.errors.some((e) => /fallback/.test(e) && /diagram/.test(e)));
  const none = join(scratch, 'none');
  write(join(none, 'plan', 'cue-sheet.json'), read(join(fixtures, 'cue-sheet.json')));
  const n = run(none);
  assert.equal(n.code, 1);
  assert.match(n.out, /no model-written layers/);
});

test('the resolver turns regions and anchors into renderer-shaped timed graphics and rejects what it cannot place', () => {
  const root = job('resolve');
  const r = spawnSync(process.execPath, [resolver, root], { encoding: 'utf8', windowsHide: true });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  const graphics = read(join(root, 'plan', 'model-specs', 'timed-graphics.json'));
  assert.deepEqual(Object.keys(graphics), ['overlays']);
  assert.equal(graphics.overlays.length, 3);
  const allowed = new Set(['assetId', 'x', 'y', 'width', 'height', 'startSeconds', 'endSeconds', 'visibleLabel']);
  for (const o of graphics.overlays) {
    for (const k of Object.keys(o)) assert.ok(allowed.has(k), k);
    for (const k of ['x', 'y', 'width', 'height']) assert.ok(Number.isInteger(o[k]) && o[k] >= 0, `${k} ${o[k]}`);
    assert.ok(o.endSeconds > o.startSeconds && o.startSeconds >= 0);
  }
  const callout = graphics.overlays.find((o) => o.visibleLabel === 'Opens the queue');
  assert.deepEqual([callout.x, callout.y, callout.width, callout.height], [40, 40, 480, 160]);
  assert.equal(callout.startSeconds, 1);
  const bad = job('resolve-bad', { sheet: (s) => { s.beats[0].actions[0].action_time = null; } });
  const b = spawnSync(process.execPath, [resolver, bad], { encoding: 'utf8', windowsHide: true });
  assert.equal(b.status, 1);
  assert.match(b.stdout + b.stderr, /Open queue.*no program time/);
});

// ---- fixes from the independent review of b7ba9509
const resolve_ = (root, args = []) => { const r = spawnSync(process.execPath, [resolver, root, ...args], { encoding: 'utf8', windowsHide: true }); return { code: r.status, out: r.stdout + r.stderr }; };
const item = (report, id) => report.items.find((i) => i.id === id);
const onApprove = (over = {}) => overlay({ beatId: 'S02', actionLabel: 'Approve', region: 'right-panel', text: 'Approve it', ...over });

test('a zoom is kept out of timed graphics because the compositor would paint it over the footage', () => {
  const root = job('zoom-over-pointer', { layers: (l) => { l.overlays.output.overlays[1] = onApprove({ kind: 'zoom', text: '' }); } });
  assert.equal(resolve_(root).code, 0);
  const graphics = read(join(root, 'plan', 'model-specs', 'timed-graphics.json'));
  assert.ok(!graphics.overlays.some((o) => /zoom/.test(o.assetId)), JSON.stringify(graphics));
  const { code, out, report } = run(root);
  assert.equal(code, 0, out);
  assert.equal(item(report, 'overlays[1]').geometry, 'not rendered: no crop renderer exists, so a zoom is kept out of timed graphics');
});

test('a Recast-zoomed take, an editorial crop or a panel is not checked rather than reported clear', () => {
  const recast = job('recast-full', { receipt: (r) => { r.clips.C1.recast = 'full'; }, layers: (l) => { l.overlays.output.overlays[1] = onApprove(); } });
  const r = run(recast);
  assert.equal(item(r.report, 'overlays[1]').geometry, 'not checked: Recast zoom not modelled');
  assert.ok(!r.report.items.some((i) => i.geometry === 'clear'));
  assert.ok(r.report.checks.notPerformed.some((n) => n.check === 'geometry' && n.reason === 'not checked: Recast zoom not modelled'));
  for (const [key, value, reason] of [['sourceRegion', { x: 0, y: 0, width: 0.5, height: 0.5 }, 'not checked: editorial crop not modelled'], ['destinationRect', { x: 400, y: 200, width: 800, height: 500 }, 'not checked: editorial panel not modelled']]) {
    const root = job(`compose-${key}`, {
      sheet: (s) => { s.inputs.composeMap = { path: 'output/film-compose-map.json', sha256: 'x' }; },
      after: (r2) => write(join(r2, 'output', 'film-compose-map.json'), { generator: 'media-studio/compose-screencast', groups: [{ clipId: 'C1', segments: ['S01', 'S02'], startSeconds: 0, needSeconds: 12, [key]: value }] }),
    });
    const c = run(root);
    assert.equal(item(c.report, 'overlays[0]').geometry, reason, key);
    assert.equal(c.report.inputs.composeMap.path, 'output/film-compose-map.json');
  }
});

test('an item whose window holds an action without geometry is partial, never clear', () => {
  const root = job('partial', { receipt: (r) => { delete r.clips.C1.actions[6].x; delete r.clips.C1.actions[6].y; } });
  const { code, out, report } = run(root);
  assert.equal(code, 0, out);
  assert.equal(item(report, 'overlays[0]').geometry, 'partial');
  assert.ok(report.checks.notPerformed.some((n) => n.check === 'geometry' && n.item === 'overlays[0]' && /first row/.test(n.reason)));
});

test('a diagram spanning two clips is checked against both clips', () => {
  const root = job('two-clips', {
    sheet: (s) => { s.beats[1].screen.clip = 'C2'; },
    receipt: (r) => { r.clips.C2 = { ...structuredClone(r.clips.C1), file: 'clips/C2.webm', segments: ['S02'] }; r.clips.C1.segments = ['S01']; },
    layers: (l) => { Object.assign(l.diagram.output.diagrams[0], { beatId: 'S01', toBeatId: 'S02', placement: 'right-panel' }); l.overlays.output.overlays.pop(); },
  });
  const { code, report } = run(root);
  assert.equal(code, 1);
  assert.ok(report.errors.some((e) => /diagram\[0\]/.test(e) && /Approve/.test(e)), report.errors.join('\n'));
});

test('a fullscreen insert over a span with no clip is not checked, never "at a pause"', () => {
  const root = job('fullscreen-card', { sheet: (s) => { s.beats[1].screen = { clip: null, kind: 'card' }; }, layers: (l) => { l.diagram.output.diagrams[0].placement = 'fullscreen'; l.overlays.output.overlays.pop(); } });
  const { report } = run(root);
  assert.equal(item(report, 'diagram[0]').geometry, 'not checked: no recorded clip in this span');
});

test('an action window is trimmed to its beat at both ends', () => {
  const root = job('clamp', { sheet: (s) => { s.beats[1].actions[0].action_time = 6.1; }, layers: (l) => { l.overlays.output.overlays[1] = onApprove({ region: 'top-right' }); } });
  assert.equal(resolve_(root).code, 0);
  const placed = read(join(root, 'plan', 'model-specs', 'timed-graphics.json')).overlays.find((o) => o.visibleLabel === 'Approve it');
  assert.equal(placed.startSeconds, 6);
  assert.ok(!run(root).report.errors.some((e) => /outside/.test(e)));
});

test('the resolver writes nothing without layers, and the gate binds what it wrote', () => {
  const bare = join(scratch, 'resolve-none');
  write(join(bare, 'plan', 'cue-sheet.json'), read(join(fixtures, 'cue-sheet.json')));
  const r = resolve_(bare);
  assert.equal(r.code, 1);
  assert.match(r.out, /no model-written layers/);
  assert.ok(!existsSync(join(bare, 'plan', 'model-specs')));
  const root = job('bind-graphics');
  assert.equal(resolve_(root).code, 0);
  const path = join(root, 'plan', 'model-specs', 'timed-graphics.json');
  assert.equal(run(root).report.inputs.timedGraphics.sha256, sha(path));
  const g = read(path); g.overlays[0].x += 10; write(path, g);
  const stale = run(root);
  assert.equal(stale.code, 1);
  assert.ok(stale.report.errors.some((e) => /timed-graphics.json is stale/.test(e)), stale.report.errors.join('\n'));
});

test('two diagrams at once, or a diagram under an overlay, fail', () => {
  const both = job('two-diagrams', { layers: (l) => { l.diagram.output.diagrams.push({ ...l.diagram.output.diagrams[0], placement: 'right-panel' }); l.overlays.output.overlays.pop(); } });
  assert.ok(run(both).report.errors.some((e) => /two supporting diagrams/.test(e)));
  const under = job('diagram-under-overlay', { layers: (l) => { l.overlays.output.overlays[1].region = 'bottom-left'; } });
  assert.ok(run(under).report.errors.some((e) => /diagram\[0\]/.test(e) && /overlays\[1\]/.test(e) && /overlap/.test(e)));
});

test('a result on screen without a box counts as missing geometry, so the item is partial', () => {
  const root = job('result-no-box', { receipt: (r) => { r.clips.C1.expectations[0].targetBox = null; } });
  const { code, out, report } = run(root);
  assert.equal(code, 0, out);
  assert.equal(item(report, 'overlays[1]').geometry, 'partial');
  assert.ok(report.checks.notPerformed.some((n) => n.item === 'overlays[1]' && /Status reads Approved/.test(n.reason)));
});
