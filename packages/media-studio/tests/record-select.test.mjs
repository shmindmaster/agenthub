import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { bindHelpers, EventLog, BeatTracker } from '../kit/screencast/record-lib.mjs';

function fixture(t, overrides = {}, pageOverrides = {}) {
  const rawDir = mkdtempSync(join(tmpdir(), 'native-select-'));
  t.after(() => rmSync(rawDir, { recursive: true, force: true }));
  let value = 'reviewer';
  const el = { tagName: 'SELECT', multiple: false, options: [{ value: 'reviewer', label: 'Content reviewer' }, { value: 'owner', label: 'Work owner' }] };
  const calls = [];
  const locator = { count: async () => 1, isVisible: async () => true, isEnabled: async () => true,
    evaluate: async (fn, arg) => fn({ ...el, selectedOptions: el.options.filter(x => x.value === value) }, arg),
    inputValue: async () => value, first: () => locator, scrollIntoViewIfNeeded: async () => {},
    boundingBox: async () => ({ x: 100, y: 200, width: 80, height: 40 }),
    selectOption: async (requested, options) => { calls.push({ requested, options }); value = requested; return [value]; },
    toString: () => 'getByLabel(Viewing as)', ...overrides };
  const page = { waitForTimeout: async () => {}, viewportSize: () => ({ width: 800, height: 600 }), mouse: { move: async () => {} },
    screenshot: async ({ path }) => { const bytes = Buffer.from(`synthetic image ${value}`); writeFileSync(path, bytes); return bytes; }, ...pageOverrides };
  const log = new EventLog(Date.now()), beats = new BeatTracker(Date.now());
  log.now = (() => { let n = 0; return () => ++n; })();
  return { h: bindHelpers(page, log, beats, { rawDir, viewport: { width: 800 }, videoSize: { width: 1600 } }), locator, log, beats, calls, rawDir, el };
}

test('native select records actual operation, readback, scaled bounds and hashed images without invented clicks', async t => {
  const f = fixture(t);
  const event = await f.h.selectOption(f.locator, 'owner', { label: 'Switch role', hold: 0 });
  assert.deepEqual(f.calls, [{ requested: 'owner', options: { timeout: 15000 } }]);
  assert.equal(event.method, 'locator.selectOption');
  assert.equal(event.beforeValue, 'reviewer'); assert.equal(event.value, 'owner');
  assert.equal(event.optionLabel, 'Work owner'); assert.equal(event.target, 'getByLabel(Viewing as)');
  assert.deepEqual(event.targetBox, { x: 200, y: 400, w: 160, h: 80 });
  assert.equal(event.x, 280); assert.equal(event.y, 440);
  assert.ok(event.tStart < event.tEnd && event.tEnd <= event.t);
  for (const ref of [event.beforeImage, event.afterImage]) assert.equal(ref.sha256, createHash('sha256').update(readFileSync(join(f.rawDir, ref.path))).digest('hex'));
  assert.notEqual(event.beforeImage.sha256, event.afterImage.sha256);
  assert.equal(f.log.summary().selections, 1); assert.equal(f.log.summary().clicks, 0); assert.equal(f.log.summary().keystrokes, 0);
  assert.equal(f.beats.marks.length, 1);
});

test('invalid selection inputs fail before native operation with a failure receipt', async t => {
  const variants = [
    { overrides: { count: async () => 2 } }, { overrides: { isVisible: async () => false } },
    { overrides: { isEnabled: async () => false } }, { mutate: el => { el.multiple = true; } },
    { mutate: el => { el.tagName = 'INPUT'; } }, { mutate: el => { el.options.push({ value: 'owner', label: 'Duplicate' }); } },
    { mutate: el => { el.options[1].disabled = true; } },
    { mutate: el => { el.options[1].parentElement = { tagName: 'OPTGROUP', disabled: true }; } },
    { value: 'missing' }, { value: 7 }, { label: '' }, { timeout: -1 },
  ];
  for (const variant of variants) {
    const f = fixture(t, variant.overrides); variant.mutate?.(f.el);
    await assert.rejects(f.h.selectOption(f.locator, variant.value ?? 'owner', { label: variant.label ?? 'Role', timeout: variant.timeout }), /failed at validation/);
    assert.equal(f.calls.length, 0); assert.equal(f.log.summary().selections, 0);
    assert.equal(f.log.events.at(-1).type, 'select-failed'); assert.equal(f.beats.marks.length, 0);
  }
});

test('native action, image and readback failures never produce success and redact provider errors', async t => {
  for (const [overrides, pageOverrides, stage] of [
    [{ selectOption: async () => { throw new Error('secret provider payload'); } }, {}, 'native-selection'],
    [{ inputValue: async () => 'wrong' }, {}, 'readback'],
    [{}, { screenshot: async () => { throw new Error('secret screenshot payload'); } }, 'before-image'],
  ]) {
    const f = fixture(t, overrides, pageOverrides);
    await assert.rejects(f.h.selectOption(f.locator, 'owner', { label: 'Role' }), new RegExp(`failed at ${stage}`));
    assert.equal(f.log.summary().selections, 0); assert.equal(f.beats.marks.length, 0);
    assert.equal(f.log.events.at(-1).stage, stage); assert.ok(!JSON.stringify(f.log.events).includes('secret'));
  }
});
