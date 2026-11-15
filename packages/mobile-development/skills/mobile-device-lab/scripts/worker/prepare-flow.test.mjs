// Behavior tests for the lab worker's flow preparation (SH-4390): a
// development-client deep link must follow EVERY launchApp in the copy, and
// the committed flow must stay untouched. Fixtures are throwaway files under
// the OS temp directory, never this checkout.
//
// Run: node --test packages/mobile-development/skills/mobile-device-lab/scripts/worker/prepare-flow.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { prepareFlow } from './prepare-flow.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const script = path.join(here, 'prepare-flow.mjs');
const link = 'exp+abacare://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A8081';
const openLink = `- openLink: "${link}"`;
// The dev client drops a deep link that arrives while its activity is still
// being created, so the copy waits for the Expo launcher's home first.
const settle = [
  '- extendedWaitUntil:',
  '    visible: "New development server"',
  '    timeout: 15000',
  '    optional: true',
];
const settleLf = settle.join('\n');
const settleCrlf = settle.join('\r\n');

const scratch = mkdtempSync(path.join(tmpdir(), 'prepare-flow-'));
after(() => rmSync(scratch, { recursive: true, force: true }));

test('inserts the settle wait and link after each launchApp clearState block, true and false', () => {
  const flow = [
    'appId: ai.abacare.app',
    '---',
    '- launchApp:',
    '    clearState: true',
    '- assertVisible: "Hi"',
    '- launchApp:',
    '    clearState: false',
    '- assertVisible: "Back"',
    '',
  ].join('\n');
  const prepared = prepareFlow(flow, link);
  assert.equal(
    prepared,
    [
      'appId: ai.abacare.app',
      '---',
      '- launchApp:',
      '    clearState: true',
      ...settle,
      openLink,
      '- assertVisible: "Hi"',
      '- launchApp:',
      '    clearState: false',
      ...settle,
      openLink,
      '- assertVisible: "Back"',
      '',
    ].join('\n'),
  );
});

test('inserts the settle wait and link after a bare launchApp with no clearState', () => {
  const prepared = prepareFlow('- launchApp:\n- assertVisible: "Hi"\n', link);
  assert.equal(prepared, `- launchApp:\n${settleLf}\n${openLink}\n- assertVisible: "Hi"\n`);
});

test('keeps inline comments and all launchApp options before the inserted steps', () => {
  const flow = [
    '- launchApp:',
    '    clearState: true # reset the fixture',
    '    permissions:',
    '      notifications: allow',
    '    appId: ai.example.app',
    '- assertVisible: "Ready"',
    '',
  ].join('\n');
  assert.equal(
    prepareFlow(flow, link),
    [
      '- launchApp:',
      '    clearState: true # reset the fixture',
      '    permissions:',
      '      notifications: allow',
      '    appId: ai.example.app',
      ...settle,
      openLink,
      '- assertVisible: "Ready"',
      '',
    ].join('\n'),
  );
});

test('leaves existing openLink steps and all other content unchanged', () => {
  const flow = '- openLink: abacare://home\n- launchApp:\n    clearState: true\n- tapOn: "Me"\n';
  const prepared = prepareFlow(flow, link);
  assert.equal(prepared, `- openLink: abacare://home\n- launchApp:\n    clearState: true\n${settleLf}\n${openLink}\n- tapOn: "Me"\n`);
  assert.equal(prepareFlow('- tapOn: "Me"\n', link), '- tapOn: "Me"\n');
});

test('preserves CRLF line endings and a missing trailing newline', () => {
  const prepared = prepareFlow('- launchApp:\r\n    clearState: true\r\n', link);
  assert.equal(prepared, `- launchApp:\r\n    clearState: true\r\n${settleCrlf}\r\n${openLink}\r\n`);
  assert.equal(prepareFlow('- launchApp:', link), `- launchApp:\n${settleLf}\n${openLink}`);
});

test('refuses an empty launchUrl', () => {
  assert.throws(() => prepareFlow('- launchApp:\n', ''), /non-empty/);
  assert.throws(() => prepareFlow('- launchApp:\n', '   '), /non-empty/);
});

test('flowRewrite retargets host-side script addresses before the link is inserted', () => {
  const flow = [
    'env:',
    '  API: http://10.0.2.2:8787',
    '---',
    '- runScript:',
    '    file: ../scripts/control.js',
    '- launchApp:',
    '    clearState: true',
    '',
  ].join('\n');
  const prepared = prepareFlow(flow, link, { 'http://10.0.2.2:8787': 'http://127.0.0.1:8787' });
  assert.equal(
    prepared,
    [
      'env:',
      '  API: http://127.0.0.1:8787',
      '---',
      '- runScript:',
      '    file: ../scripts/control.js',
      '- launchApp:',
      '    clearState: true',
      ...settle,
      openLink,
      '',
    ].join('\n'),
  );
  // The inserted link keeps the emulator-facing address even when the
  // rewrite map mentions the same host: rewrite runs before insertion.
  const metroRewrite = prepareFlow('- launchApp:\n', link, { '10.0.2.2': '127.0.0.1' });
  assert.equal(metroRewrite, `- launchApp:\n${settleLf}\n${openLink}\n`);
});

test('flowRewrite refuses malformed maps', () => {
  assert.throws(() => prepareFlow('- launchApp:\n', link, null), /object/);
  assert.throws(() => prepareFlow('- launchApp:\n', link, []), /object/);
  assert.throws(() => prepareFlow('- launchApp:\n', link, { '': 'x' }), /string pairs/);
  assert.throws(() => prepareFlow('- launchApp:\n', link, { a: 5 }), /string pairs/);
});

test('CLI applies the rewrite JSON argument', () => {
  const source = path.join(scratch, 'rewrite.yaml');
  const output = path.join(scratch, 'rewrite-prepared.yaml');
  const flow = 'env:\n  API: http://10.0.2.2:8787\n---\n- launchApp:\n    clearState: true\n';
  writeFileSync(source, flow, 'utf8');
  const result = spawnSync(
    process.execPath,
    [script, source, link, output, '{"http://10.0.2.2:8787":"http://127.0.0.1:8787"}'],
    { encoding: 'utf8' },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.match(readFileSync(output, 'utf8'), /API: http:\/\/127\.0\.0\.1:8787/);
  assert.equal(readFileSync(source, 'utf8'), flow);
  const badJson = spawnSync(process.execPath, [script, source, link, output, '{oops'], { encoding: 'utf8' });
  assert.equal(badJson.status, 1);
});

test('CLI writes the prepared copy and never touches the committed flow', () => {
  const source = path.join(scratch, '06-identity-gate.yaml');
  const output = path.join(scratch, 'flow-prepared.yaml');
  const flow = '- launchApp:\n    clearState: true\n- extendedWaitUntil:\n    visible: "Hi"\n';
  writeFileSync(source, flow, 'utf8');
  const result = spawnSync(process.execPath, [script, source, link, output], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(source, 'utf8'), flow);
  assert.equal(readFileSync(output, 'utf8'), prepareFlow(flow, link));
});

test('CLI refuses missing arguments and an unreadable flow', () => {
  const noArgs = spawnSync(process.execPath, [script], { encoding: 'utf8' });
  assert.equal(noArgs.status, 2);
  const missing = spawnSync(
    process.execPath,
    [script, path.join(scratch, 'absent.yaml'), link, path.join(scratch, 'out.yaml')],
    { encoding: 'utf8' },
  );
  assert.equal(missing.status, 1);
  assert.match(missing.stderr, /prepare-flow:/);
});
