// record-lib unit tests with a fake page object (no browser, no playwright install): the tap helper and device resolution.
// Run: node --test tests/record-lib.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const pkg = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const libFile = join(pkg, 'kit', 'screencast', 'record-lib.mjs');
const { bindHelpers, EventLog, BeatTracker, resolveDevice } = await import(pathToFileURL(libFile).href);

const fakeLocator = (box = { x: 100, y: 200, width: 80, height: 40 }) => {
  const calls = [];
  const l = { calls, first: () => l, scrollIntoViewIfNeeded: async () => {}, boundingBox: async () => box, tap: async (o) => { calls.push(['tap', o]); }, click: async (o) => { calls.push(['click', o]); }, toString: () => 'getByRole(button)' };
  return l;
};
const fakePage = () => ({ waitForTimeout: async () => {}, viewportSize: () => ({ width: 390, height: 844 }), mouse: { move: async () => {}, wheel: async () => {} } });
const setup = (opts) => {
  const t0 = Date.now();
  const log = new EventLog(t0), beats = new BeatTracker(t0);
  return { log, beats, h: bindHelpers(fakePage(), log, beats, opts) };
};

test('importing record-lib needs no playwright install', () => {
  assert.equal(typeof bindHelpers, 'function');
  assert.equal(typeof setup({}).h.tap, 'function');
});

function uploadFixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'record-upload-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const file = join(dir, 'synthetic.csv');
  writeFileSync(file, 'period,amount\nSeptember,42\n');
  return { dir, file };
}

test('upload selects exact hashed bytes on a hidden file input and logs only a completed upload', async (t) => {
  const { file } = uploadFixture(t), { log, beats, h } = setup({});
  let selected;
  log.now = (() => { let n = 0; return () => ++n; })();
  const loc = { count: async () => 1, evaluate: async (fn) => fn({ tagName: 'INPUT', type: 'file' }),
    setInputFiles: async (payload) => { assert.equal(log.events.length, 0); selected = payload; writeFileSync(file, 'changed'); },
    toString: () => 'modal.locator(input[type=file])' };
  const event = await h.uploadFile(loc, file, { label: 'Select synthetic September CSV', hold: 0 });
  assert.equal(selected.buffer.toString(), 'period,amount\nSeptember,42\n');
  assert.deepEqual(event.file, { name: 'synthetic.csv', bytes: selected.buffer.length,
    sha256: createHash('sha256').update(selected.buffer).digest('hex'), mimeType: 'text/csv' });
  assert.equal(event.method, 'locator.setInputFiles');
  assert.equal(event.target, 'modal.locator(input[type=file])');
  assert.ok(event.tStart < event.tEnd && event.tEnd <= event.t);
  assert.deepEqual(log.events.map(e => e.type), ['upload']);
  assert.equal(log.summary().uploads, 1);
  assert.equal(log.summary().clicks, 0);
  assert.equal(log.summary().pointerMoves, 0);
  assert.equal(beats.marks.length, 1);
  assert.ok(!JSON.stringify(log.events).includes(file), 'receipt omits private source path');
});

test('upload rejects missing or directory sources, ambiguous/non-file locators and unlabelled actions', async (t) => {
  const { dir, file } = uploadFixture(t), { log, beats, h } = setup({});
  let calls = 0;
  const loc = { count: async () => 1, evaluate: async () => true, setInputFiles: async () => { calls++; } };
  const o = { label: 'Select CSV', hold: 0 };
  await assert.rejects(h.uploadFile(loc, file), /nonempty action label/);
  await assert.rejects(h.uploadFile(loc, '', o), /local file path/);
  await assert.rejects(h.uploadFile(loc, join(dir, 'missing.csv'), o));
  await assert.rejects(h.uploadFile(loc, dir, o), /regular file/);
  for (const count of [0, 2]) await assert.rejects(h.uploadFile({ ...loc, count: async () => count }, file, o), /exactly one/);
  await assert.rejects(h.uploadFile({ ...loc, evaluate: async () => false }, file, o), /input\[type=file\]/);
  await assert.rejects(h.uploadFile(loc, file, { ...o, mimeType: '' }), /mimeType/);
  assert.equal(calls, 0); assert.deepEqual(log.events, []); assert.deepEqual(beats.marks, []);
});

test('failed native upload never records success or a beat', async (t) => {
  const { file } = uploadFixture(t), { log, beats, h } = setup({});
  const loc = { count: async () => 1, evaluate: async () => true, setInputFiles: async () => { throw new Error('detached input'); } };
  await assert.rejects(h.uploadFile(loc, file, { label: 'Select CSV' }), /detached input/);
  assert.deepEqual(log.events, []); assert.deepEqual(beats.marks, []);
});

test('tap on a touch context calls locator.tap, logs one tap event and no pointer moves', async () => {
  const { log, beats, h } = setup({ hasTouch: true });
  const loc = fakeLocator();
  await h.tap(loc, { label: 'Approve', hold: 0 });
  assert.deepEqual(loc.calls.map((c) => c[0]), ['tap']);
  assert.equal(loc.calls[0][1].force, true);
  assert.deepEqual(loc.calls[0][1].position, { x: 40, y: 20 });
  assert.deepEqual(log.events.map((e) => e.type), ['tap']);
  const e = log.events[0];
  assert.equal(e.x, 140); assert.equal(e.y, 220);
  assert.equal(e.label, 'Approve'); assert.equal(e.target, 'Approve');
  assert.ok(Number.isFinite(e.tStart) && e.tStart <= e.t);
  assert.equal(log.summary().taps, 1);
  assert.equal(log.summary().pointerMoves, 0);
  assert.deepEqual(beats.marks.map((m) => m.label), ['Approve']);
  assert.deepEqual(beats.marks[0].box, { x: 100, y: 200, w: 80, h: 40 });
});

test('tap without touch falls back to a click (eased approach first) and still logs type tap', async () => {
  const { log, h } = setup({ hasTouch: false });
  const loc = fakeLocator();
  await h.tap(loc, { label: 'Approve', hold: 0 });
  assert.deepEqual(loc.calls.map((c) => c[0]), ['click']);
  assert.deepEqual(log.events.map((e) => e.type), ['move', 'move', 'move', 'tap']);
  assert.equal(log.events.at(-1).label, 'Approve');
  assert.equal(log.summary().taps, 1);
  assert.equal(log.summary().clicks, 0, 'logged as a tap, not a click');
});

test('tap with no hasTouch option behaves as no touch; the unlabelled target is the locator description', async () => {
  const { log, h } = setup(undefined ?? {});
  const loc = fakeLocator();
  await h.tap(loc, { hold: 0 });
  assert.equal(loc.calls[0][0], 'click');
  assert.equal(log.events.at(-1).label, null);
  assert.equal(log.events.at(-1).target, 'getByRole(button)');
});

test('resolveDevice: none named -> null, known -> descriptor, unknown -> error', () => {
  const devices = { 'iPhone 13': { viewport: { width: 390, height: 664 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true } };
  assert.equal(resolveDevice({}, devices), null);
  assert.equal(resolveDevice({ device: 'iPhone 13' }, devices), devices['iPhone 13']);
  assert.throws(() => resolveDevice({ device: 'Nokia 3310' }, devices), /unknown Playwright device "Nokia 3310"/);
});

test('startRecording applies the device descriptor before the explicit viewport and DSF, and passes touch to the helpers (source check)', () => {
  const src = readFileSync(libFile, 'utf8');
  assert.match(src, /\.\.\.\(device \|\| \{\}\),\s+viewport,\s+(?:\/\/[^\n]*\n\s+)?deviceScaleFactor: (?:mobile \? 1 : )?opts\.deviceScaleFactor \|\| device\?\.deviceScaleFactor \|\| 2/);
  assert.match(src, /opts\.isMobile !== undefined/);
  assert.match(src, /opts\.hasTouch !== undefined/);
  assert.match(src, /hasTouch: opts\.hasTouch \?\? device\?\.hasTouch \?\? false/);
});

test('record-job --ratio picks options.viewports[r] and writes ratio, device, viewport and DSF into every receipt clip (source check)', () => {
  const src = readFileSync(join(pkg, 'kit', 'screencast', 'record-job.mjs'), 'utf8');
  assert.match(src, /--ratio/);
  assert.match(src, /options\.viewports/);
  assert.match(src, /ratio: ratioOpt \|\| reducedRatio\(rec\.viewport\)/);
  assert.match(src, /device: capture\.device/);
  assert.match(src, /deviceScaleFactor: (?:options\.mobileLayout \? options\.mobileLayout\.scale : )?capture\.deviceScaleFactor \|\| 2/);
  assert.match(src, /resolution: capture\.videoSize \|\| capture\.viewport/);
  // A --ratio entry is a CSS viewport: it records and Recasts at viewport x DSF (Playwright records at the size it is given).
  assert.match(src, /capture\.videoSize = \{ width: Math\.round\(vp\.width \* dsf\), height: Math\.round\(vp\.height \* dsf\) \}/);
  assert.match(src, /videoSize: capture\.videoSize/);
  assert.doesNotMatch(src, /options\.viewport\b(?!s)[^;\n]*resolution|resolution: options\.viewport/, 'no remaining direct use of options.viewport for recording');
});


function fillLocator(overrides = {}) {
  return { ...fakeLocator(), count: async () => 1, evaluate: async () => 'month',
    fill: async () => {}, inputValue: async () => '2026-09', ...overrides };
}
test('native fill records actual month readback and scaled bounds without a click or keystrokes', async () => {
  const { log, beats, h } = setup({ videoSize: { width: 780 }, viewport: { width: 390 } });
  log.now = (() => { let n = 0; return () => ++n; })();
  const calls = [];
  const loc = fillLocator({ fill: async (...args) => { assert.equal(log.events.some(e => e.type === 'fill'), false); calls.push(args); } });
  const event = await h.fillValue(loc, '2026-09', { label: 'Declared reporting month', target: 'month control', hold: 0 });
  assert.deepEqual(calls, [['2026-09', { timeout: 15000 }]]);
  assert.equal(event.method, 'locator.fill'); assert.equal(event.inputType, 'month'); assert.equal(event.value, '2026-09');
  assert.equal(event.target, 'month control');
  assert.deepEqual(event.targetBox, { x: 200, y: 400, w: 160, h: 80 });
  assert.ok(event.tStart < event.tEnd && event.tEnd <= event.t);
  assert.equal(log.summary().fills, 1); assert.equal(log.summary().clicks, 0); assert.equal(log.summary().keystrokes, 0);
  assert.ok(log.summary().pointerMoves > 0); assert.equal(beats.marks.length, 1);
  for (const key of ['x', 'y', 'chars']) assert.equal(Object.hasOwn(event, key), false);
});
test('native fill rejects ambiguous, secret, unsupported and unlabelled controls before execution', async () => {
  const { log, beats, h } = setup({}); let calls = 0;
  const loc = fillLocator({ fill: async () => { calls++; } });
  await assert.rejects(h.fillValue(loc, '2026-09'), /nonempty action label/);
  await assert.rejects(h.fillValue(loc, 202609, { label: 'Month' }), /string value/);
  for (const count of [0, 2]) await assert.rejects(h.fillValue({ ...loc, count: async () => count }, '2026-09', { label: 'Month' }), /exactly one/);
  for (const kind of ['password', 'file', 'hidden', 'button', null]) await assert.rejects(h.fillValue({ ...loc, evaluate: async () => kind }, '2026-09', { label: 'Month' }), /nonsecret editable/);
  assert.equal(calls, 0); assert.deepEqual(log.events, []); assert.deepEqual(beats.marks, []);
});
test('native fill records no success or beat after native failure or mismatched readback', async () => {
  for (const changes of [{ fill: async () => { throw new Error('detached field'); } }, { inputValue: async () => '2026-08' }]) {
    const { log, beats, h } = setup({});
    await assert.rejects(h.fillValue(fillLocator(changes), '2026-09', { label: 'Month', hold: 0 }), /detached field|readback/);
    assert.equal(log.summary().fills, 0); assert.deepEqual(beats.marks, []);
  }
});
