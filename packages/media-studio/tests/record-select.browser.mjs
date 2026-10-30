// Synthetic remote-only integration: node --test packages/media-studio/tests/record-select.browser.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from 'playwright';
import { bindHelpers, EventLog, BeatTracker } from '../kit/screencast/record-lib.mjs';

test('real native select fires the application change handler and rejects disabled options', async t => {
  const rawDir = mkdtempSync(join(tmpdir(), 'select-browser-'));
  const browser = await chromium.launch({ headless: true });
  t.after(async () => { await browser.close(); rmSync(rawDir, { recursive: true, force: true }); });
  const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
  await page.setContent(`<label>Viewing as<select><option value="reviewer">Content reviewer</option><option value="owner">Work owner</option><option value="disabled" disabled>Unavailable</option></select></label><output>Content reviewer active</output><script>document.querySelector('select').addEventListener('change', e => document.querySelector('output').textContent = e.target.selectedOptions[0].label + ' active')</script>`);
  const log = new EventLog(Date.now()), beats = new BeatTracker(Date.now());
  const h = bindHelpers(page, log, beats, { rawDir });
  const event = await h.selectOption(page.getByLabel('Viewing as'), 'owner', { label: 'Switch synthetic role', hold: 0 });
  await h.expect(page.locator('output').filter({ hasText: 'Work owner active' }), 'Role change processed', { hold: 0 });
  assert.equal(event.value, 'owner'); assert.equal(log.summary().selections, 1);
  assert.equal(log.summary().clicks, 0); assert.equal(log.summary().expectationsObserved, 1);
  await assert.rejects(h.selectOption(page.getByLabel('Viewing as'), 'disabled', { label: 'Unavailable role' }), /failed at validation/);
  assert.equal(await page.getByLabel('Viewing as').inputValue(), 'owner');
  assert.equal(log.summary().selections, 1); assert.equal(log.events.at(-1).type, 'select-failed');
});
