// Capture pre-flight: static checks on scenes.mjs against the locked narration, the capture plan and the cue plan, run before
// record-job.mjs opens a browser. Pure JSON/text fixtures, no ffmpeg. Run: node --test tests/capture-preflight.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const gate = join(pkg, 'scripts', 'validate-capture-preflight.mjs');
const recordJob = join(pkg, 'kit', 'screencast', 'record-job.mjs');
const scratch = mkdtempSync(join(tmpdir(), 'capture-preflight-'));
test.after(() => rmSync(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }));
const write = (p, data) => { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, typeof data === 'string' ? data : JSON.stringify(data, null, 2)); };
const sha = (p) => createHash('sha256').update(readFileSync(p)).digest('hex');
const run = (root, args = []) => {
  const r = spawnSync(process.execPath, [gate, root, ...args], { encoding: 'utf8', windowsHide: true });
  const report = existsSync(join(root, 'qa', 'capture-preflight.json')) ? JSON.parse(readFileSync(join(root, 'qa', 'capture-preflight.json'), 'utf8')) : null;
  return { code: r.status, out: `${r.stdout}${r.stderr}`, report };
};

// ---- a two-scene job that passes
const SCENES = `// S05 types a name and approves; S06 reads the queue.
import fs from 'node:fs';
export const order = ['S05', 'S06'];
export const options = { baseUrl: 'http://127.0.0.1:8080' };
const NAME = 'Alicia Moreno';
export const scenes = {
  // S05 - "name" -> type the name; "approve" -> click Approve; result "plan"
  async S05(h, ctx) {
    await h.go('/plans');
    await h.typeText(h.page.getByLabel('Name'), NAME, { label: 'type name', hold: 150 });
    await h.click(h.page.getByRole('button', { name: 'Approve' }), { label: 'Approve' });
    await h.expect(h.page.getByText('Plan approved'), 'plan approved');
  },
  S06: async (h, ctx) => {
    await h.pointAt(h.page.getByText('Queue'), { label: 'queue rows' });
  },
};
`;
const TIMELINE = { durationSeconds: 10, segments: [
  { id: 'S05', scene: 'S05', text: 'Type the name, then approve the plan.', startSeconds: 0, durationSeconds: 6 },
  { id: 'S06', scene: 'S06', text: 'The queue shows every approved plan.', startSeconds: 6, durationSeconds: 4 },
] };
const CUE_PLAN = { voiceFirst: true, beats: {
  S05: { actions: [{ label: 'type name', keywords: ['name'] }, { label: 'Approve', keywords: ['approve'] }], result: { label: 'plan approved', keywords: ['plan'] } },
  S06: { actions: [{ label: 'queue rows', keywords: ['queue'] }], result: { label: 'rows visible', keywords: ['approved'] } },
} };
const CAPTURE_PLAN = { scenes: [
  { sceneId: 'S05', kind: 'interaction', action: 'type and click', expectedResult: 'Plan approved', clip: 'clips/S05.webm', startState: 'a', resultState: 'b', provesClaim: 'c' },
  { sceneId: 'S06', kind: 'interaction', action: 'point', expectedResult: 'rows', clip: 'clips/S06.webm', startState: 'a', resultState: 'b', provesClaim: 'c' },
] };
const STORYBOARD = { kind: 'product-screencast', beats: [{ id: 'S05', visualMode: 'screen' }, { id: 'S06', visualMode: 'screen' }] };

function job(name, over = {}) {
  const root = join(scratch, name);
  write(join(root, 'job.json'), { kind: 'product-screencast', repositoryWritePolicy: 'read-only' });
  write(join(root, 'capture', 'scenes.mjs'), over.scenes ?? SCENES);
  write(join(root, 'story', 'narration-timeline.json'), over.timeline ?? TIMELINE);
  if (over.capturePlan !== null) write(join(root, 'story', 'capture-plan.json'), over.capturePlan ?? CAPTURE_PLAN);
  if (over.storyboard !== null) write(join(root, 'story', 'storyboard.json'), over.storyboard ?? STORYBOARD);
  if (over.cuePlan !== null) write(join(root, 'story', 'cue-plan.json'), over.cuePlan ?? CUE_PLAN);
  return root;
}
const mutate = (base, fn) => { const c = structuredClone(base); fn(c); return c; };

// ---- PASS

test('PASS: two scenes, order, timeline, plans and keywords agree, typing within budget', () => {
  const root = job('pass');
  const r = run(root);
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.ok, true);
  assert.equal(r.report.generator, 'media-studio/validate-capture-preflight');
  assert.deepEqual(r.report.errors, []);
  assert.deepEqual(r.report.warnings, []);
  assert.deepEqual(r.report.ids.order, ['S05', 'S06']);
  assert.deepEqual(r.report.ids.scenes, ['S05', 'S06']);
  assert.deepEqual(r.report.ids.timeline.sort(), ['S05', 'S06']);
  assert.deepEqual(r.report.ids.storyboardScreen, ['S05', 'S06']);
  assert.deepEqual(r.report.ids.capturePlanInteraction, ['S05', 'S06']);
  assert.deepEqual(r.report.ids.cuePlan, ['S05', 'S06']);
  // 'Alicia Moreno' is 13 characters, typed through the NAME constant: 13 * 0.055 + 0.85
  assert.equal(r.report.typing.S05.chars, 13);
  assert.equal(r.report.typing.S05.seconds, 1.565);
  assert.equal(r.report.typing.S05.budget, 6);
  assert.equal(r.report.typing.S06, undefined, 'a scene that types nothing has no typing entry');
  assert.equal(r.report.inputs.scenes.path, 'capture/scenes.mjs');
  assert.equal(r.report.inputs.scenes.sha256, sha(join(root, 'capture', 'scenes.mjs')));
  assert.equal(r.report.inputs.timeline.path, 'story/narration-timeline.json');
  assert.equal(r.report.inputs.cuePlan.sha256, sha(join(root, 'story', 'cue-plan.json')));
  assert.equal(r.report.thresholds.typingMs, 55);
  assert.equal(r.report.thresholds.typingOverheadS, 0.85);
  const summary = JSON.parse(r.out.trim().split('\n').at(-1));
  assert.equal(summary.ok, true);
  assert.equal(summary.out, 'qa/capture-preflight.json');
});

test('every scene-declaration form is recognised: async NAME(, NAME: async, NAME(, quoted keys, arrow bodies', () => {
  const scenes = `export const order = ['A1', 'A2', 'A3', 'A4'];
export const scenes = {
  async A1(h) { await h.click(x, { label: 'one' }); },
  A2: async function (h) { await h.click(x, { label: 'two' }); },
  A3(h) { return h.click(x, { label: 'three' }); },
  'A4': async (h) => { await h.pointAt(x, { label: 'four' }); },
};`;
  const timeline = { segments: ['A1', 'A2', 'A3', 'A4'].map((id, i) => ({ id, scene: id, text: `Line ${id} here`, startSeconds: i * 3, durationSeconds: 3 })) };
  const r = run(job('forms', { scenes, timeline, capturePlan: null, storyboard: null, cuePlan: null }));
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.report.ids.scenes, ['A1', 'A2', 'A3', 'A4']);
});

test('comments and strings that look like code do not create scenes', () => {
  const scenes = `export const order = ['S05'];
export const scenes = {
  // async S99(h) { } is only a comment
  async S05(h) {
    /* S98: async (h) => {} */
    await h.click(x, { label: 'say async S97(h) {}' });
  },
};`;
  const timeline = { segments: [{ id: 'S05', scene: 'S05', text: 'Hello there world', startSeconds: 0, durationSeconds: 3 }] };
  const r = run(job('comments', { scenes, timeline, capturePlan: null, storyboard: null, cuePlan: null }));
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.report.ids.scenes, ['S05']);
});

// ---- FAIL fixtures

test('FAIL: an order id without a scene function', () => {
  const scenes = SCENES.replace("['S05', 'S06']", "['S05', 'S06', 'S07']");
  const r = run(job('order-no-fn', { scenes }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /order lists S07 but capture\/scenes\.mjs exports no scene function for it/);
});

test('FAIL: a capture-plan interaction scene without a scene function', () => {
  const capturePlan = mutate(CAPTURE_PLAN, (c) => c.scenes.push({ sceneId: 'S07', kind: 'interaction', action: 'x', expectedResult: 'y', clip: 'clips/S07.webm', startState: 'a', resultState: 'b', provesClaim: 'c' }));
  const r = run(job('plan-no-fn', { capturePlan }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /capture-plan interaction scene S07 has no scene function in capture\/scenes\.mjs/);
});

test('a capture-plan card or hold scene needs no scene function', () => {
  const capturePlan = mutate(CAPTURE_PLAN, (c) => { c.scenes.push({ sceneId: 'S07', kind: 'card' }, { sceneId: 'S08', kind: 'hold' }); });
  const r = run(job('plan-card', { capturePlan }));
  assert.equal(r.code, 0, r.out);
});

test('FAIL: a scene function that is not in the timeline and not covered', () => {
  const scenes = SCENES.replace("S06: async", "S09: async").replace("['S05', 'S06']", "['S05', 'S09']");
  const r = run(job('fn-not-in-timeline', { scenes, capturePlan: null, storyboard: null, cuePlan: null }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /scene function S09 has no narration segment in story\/narration-timeline\.json and is not listed in covers/);
});

test('a covered scene is allowed: covers lets one take carry several segments', () => {
  const scenes = `export const order = ['S04'];
export const covers = { S04: ['S04', 'S05'] };
export const scenes = { async S04(h) { await h.click(x, { label: 'go' }); } };`;
  const timeline = { segments: [
    { id: 'S04', scene: 'S04', text: 'First part here', startSeconds: 0, durationSeconds: 3 },
    { id: 'S05', scene: 'S05', text: 'Second part here', startSeconds: 3, durationSeconds: 4 },
  ] };
  const r = run(job('covers', { scenes, timeline, capturePlan: null, storyboard: null, cuePlan: null }));
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.report.ids.covers, { S04: ['S04', 'S05'] });
});

test('FAIL: a cue-plan beat key that is not in the timeline', () => {
  const cuePlan = mutate(CUE_PLAN, (c) => { c.beats.S08 = { actions: [{ label: 'x', keywords: ['queue'] }] }; });
  const r = run(job('cue-key', { cuePlan }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /cue-plan beat S08 is not a segment or scene in story\/narration-timeline\.json/);
});

test('FAIL: a cue-plan keyword that is not in the narration line', () => {
  const cuePlan = mutate(CUE_PLAN, (c) => { c.beats.S05.actions[1].keywords = ['submit']; });
  const r = run(job('keyword-missing', { cuePlan }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /cue-plan beat S05 action "Approve": none of its keywords \[submit\] is in the narration "Type the name, then approve the plan\."/);
});

test('FAIL: a cue-plan result keyword that is not in the narration line', () => {
  const cuePlan = mutate(CUE_PLAN, (c) => { c.beats.S06.result.keywords = ['dashboard']; });
  const r = run(job('result-keyword-missing', { cuePlan }));
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /cue-plan beat S06 result "rows visible": none of its keywords \[dashboard\] is in the narration/);
});

test('keywords match stem-tolerantly, and a partly missing keyword list is a warning', () => {
  const cuePlan = mutate(CUE_PLAN, (c) => { c.beats.S05.actions[1].keywords = ['approving', 'submit']; });
  const r = run(job('keyword-stem', { cuePlan }));
  assert.equal(r.code, 0, r.out);
  assert.match(r.report.warnings.join('\n'), /cue-plan beat S05 action "Approve": keyword "submit" is not in the narration/);
});

test('an unnarrated cue-plan action needs no keyword in the line', () => {
  const cuePlan = mutate(CUE_PLAN, (c) => { c.beats.S05.actions.push({ label: 'trace', narrated: false, keywords: ['zebra'] }); });
  const r = run(job('unnarrated', { cuePlan }));
  assert.equal(r.code, 0, r.out);
});

test('FAIL: typing over the scene\'s narration budget', () => {
  const scenes = SCENES.replace("const NAME = 'Alicia Moreno';", `const NAME = '${'a'.repeat(120)}';`);
  const r = run(job('typing-over', { scenes }));
  assert.equal(r.code, 1, r.out);
  // 120 * 0.055 + 0.85 = 7.45 s of typing against 6 s of narration
  assert.equal(r.report.typing.S05.chars, 120);
  assert.equal(r.report.typing.S05.seconds, 7.45);
  assert.match(r.report.errors.join('\n'), /S05: typing takes 7\.45 s \(120 chars at 55 ms plus 0\.85 s per call\) but the scene's narration is 6 s/);
});

test('FAIL: a literal typeText with the text inline is counted too, and --typing-ms changes the budget', () => {
  const scenes = SCENES.replace("NAME, { label", "'0123456789012345678901234567890123456789', { label");
  const ok = run(job('typing-literal', { scenes }));
  assert.equal(ok.report.typing.S05.chars, 40);
  assert.equal(ok.code, 0, ok.out);
  const slow = run(job('typing-literal', { scenes }), ['--typing-ms', '200']);
  assert.equal(slow.code, 1, slow.out);
  assert.match(slow.report.errors.join('\n'), /S05: typing takes 8\.85 s/);
});

test('a per-call delay option is honoured and a pre-roll typeText is off the narration clock', () => {
  const scenes = SCENES
    .replace("{ label: 'type name', hold: 150 }", "{ label: 'type name', delay: 5, hold: 150 }")
    .replace("    await h.go('/plans');", "    await h.go('/plans');\n    await h.typeText(h.page.getByLabel('Note'), '" + 'z'.repeat(400) + "', { label: 'type note (pre-roll)' });");
  const r = run(job('typing-delay', { scenes }));
  assert.equal(r.code, 0, r.out);
  assert.equal(r.report.typing.S05.chars, 13);
  assert.equal(r.report.typing.S05.seconds, 0.915);
  assert.equal(r.report.typing.S05.preRollChars, 400);
});

test('typing text that cannot be resolved statically is a warning, not a pass in silence', () => {
  const scenes = SCENES.replace("NAME, { label", "buildText(ctx), { label");
  const r = run(job('typing-unresolved', { scenes }));
  assert.equal(r.code, 0, r.out);
  assert.match(r.report.warnings.join('\n'), /S05: typeText text is not a string literal or a top-level string constant/);
});

test('the narration seconds of a scene are summed over its segments and its covers', () => {
  const scenes = `export const order = ['S04'];
export const covers = { S04: ['S04', 'S05'] };
export const scenes = { async S04(h) { await h.typeText(f, '${'x'.repeat(100)}', { label: 'go' }); } };`;
  const timeline = { segments: [
    { id: 'S04', scene: 'S04', text: 'First part here', startSeconds: 0, durationSeconds: 3 },
    { id: 'S05', scene: 'S05', text: 'Second part here', startSeconds: 3, durationSeconds: 4 },
  ] };
  const r = run(job('typing-covers', { scenes, timeline, capturePlan: null, storyboard: null, cuePlan: null }));
  assert.equal(r.code, 0, r.out);                         // 100 * 0.055 + 0.85 = 6.35 s against 3 + 4 = 7 s
  assert.equal(r.report.typing.S04.budget, 7);
});

test('FAIL: missing narration timeline and missing scenes.mjs are errors', () => {
  const root = join(scratch, 'empty'); mkdirSync(root, { recursive: true });
  const r = run(root);
  assert.equal(r.code, 1, r.out);
  assert.match(r.report.errors.join('\n'), /capture\/scenes\.mjs is required/);
  assert.match(r.report.errors.join('\n'), /story\/narration-timeline\.json is required/);
});

// ---- warnings

test('WARN: a click with no label, and a storyboard screen beat without a scene function', () => {
  const scenes = SCENES.replace("await h.pointAt(h.page.getByText('Queue'), { label: 'queue rows' });", "await h.click(h.page.getByText('Queue'));");
  const storyboard = mutate(STORYBOARD, (s) => s.beats.push({ id: 'S07', visualMode: 'screen' }, { id: 'S08', visualMode: 'slide' }, { id: 'S09' }));
  const r = run(job('warnings', { scenes, storyboard }));
  assert.equal(r.code, 0, r.out);
  const w = r.report.warnings.join('\n');
  assert.match(w, /S06: scene function has no label on any click, point or type/);
  assert.match(w, /storyboard screen beat S07 has no scene function/);
  assert.match(w, /storyboard screen beat S09 has no scene function/, 'omitted visualMode on a product-screencast job is a screen beat');
  assert.doesNotMatch(w, /S08/, 'a slide beat needs no scene function');
  assert.deepEqual(r.report.ids.storyboardScreen, ['S05', 'S06', 'S07', 'S09']);
});

test('WARN: a labelled action that matches no cue-plan action label for its beat', () => {
  const scenes = SCENES.replace("{ label: 'Approve' }", "{ label: 'Confirm the plan' }");
  const r = run(job('label-mismatch', { scenes }));
  assert.equal(r.code, 0, r.out);
  assert.match(r.report.warnings.join('\n'), /S05: label "Confirm the plan" matches no cue-plan action label for this beat/);
});

test('labels used for the pre-roll, the result and the trace are not mismatches', () => {
  const scenes = SCENES.replace("{ label: 'Approve' }", "{ label: 'Approve' });\n    await h.click(y, { label: 'trace' });\n    await h.pointAt(z, { label: 'plan approved (result)' });\n    await h.click(w, { label: 'open (pre-roll)' }");
  const r = run(job('label-ignored', { scenes }));
  assert.equal(r.code, 0, r.out);
  assert.deepEqual(r.report.warnings, []);
});

test('a touch scene using h.tap is labelled, and its label is checked against the cue plan', () => {
  const scenes = SCENES.replace("await h.click(h.page.getByRole('button', { name: 'Approve' }), { label: 'Approve' });", "await h.tap(h.page.getByRole('button', { name: 'Approve' }), { label: 'Approve' });");
  const ok = run(job('tap-labelled', { scenes }));
  assert.equal(ok.code, 0, ok.out);
  assert.deepEqual(ok.report.warnings, []);
  const wrong = run(job('tap-mismatch', { scenes: scenes.replace("{ label: 'Approve' }", "{ label: 'Confirm the plan' }") }));
  assert.match(wrong.report.warnings.join('\n'), /S05: label "Confirm the plan" matches no cue-plan action label for this beat/);
  const bare = run(job('tap-unlabelled', { scenes: SCENES.replace("await h.pointAt(h.page.getByText('Queue'), { label: 'queue rows' });", "await h.tap(h.page.getByText('Queue'));") }));
  assert.match(bare.report.warnings.join('\n'), /S06: scene function has no label on any click, point or type/);
});

// ---- record-job.mjs wiring

test('record-job.mjs runs the pre-flight before recording, resolves it from the deploy layouts, and has --skip-preflight', () => {
  const src = readFileSync(recordJob, 'utf8');
  assert.match(src, /validate-capture-preflight\.mjs/);
  for (const frag of ["'..', '..', 'scripts'", "'..', '..', '_shared', 'tools'"]) assert.ok(src.includes(frag), `resolver list lacks ${frag}`);
  assert.match(src, /here, 'validate-capture-preflight\.mjs'/);
  assert.match(src, /--skip-preflight/);
  assert.ok(src.includes('capture pre-flight script not found (deploy list)'));
  assert.ok(src.includes('capture pre-flight failed: fix scene ids, keywords or typing budgets before recording'));
  assert.ok(src.includes("windowsHide: true, stdio: 'inherit'"));
  assert.match(src, /recordings\.preflight = 'skipped'/);
  assert.match(src, /recordings\.preflight = \{ ok: true, report: 'qa\/capture-preflight\.json' \}/);
  assert.ok(src.indexOf('validate-capture-preflight.mjs') < src.indexOf('for (const id of ids)'), 'the pre-flight runs before the recording loop');
  const usage = src.split('\n').slice(0, 8).join('\n');
  assert.match(usage, /--skip-preflight/, 'the usage comment lists the flag');
});
