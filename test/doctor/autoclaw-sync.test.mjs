import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { test } from 'node:test';
import { syncAutoClawPlugins } from '../../scripts/sync-autoclaw-plugins.mjs';

const base = resolve('fixture-marketplaces');
const directory = resolve(base, 'agenthub', `${'a'.repeat(40)}-${'b'.repeat(40)}`, 'marketplace');
const agenthub = {
  name: 'agenthub',
  root: resolve('fixture-agenthub'),
  directory,
  plugins: [
    { name: 'ah-example', version: '2.0.0' },
    { name: 'ah-on-demand', version: '1.0.0', disabled: true },
  ],
};
const parallel = { name: 'parallel-agent-skills', repo: 'parallel-web/parallel-agent-skills', plugins: [{ name: 'parallel' }] };

function fixture(path = directory) {
  const installed = [{ id: 'ah-example@agenthub', version: '1.0.0', enabled: false }];
  const calls = [];
  const runtime = {
    async invoke(args) {
      calls.push(args);
      if (args[1] === 'marketplace' && args[2] === 'list') return [
        { name: agenthub.name, source: { source: 'directory', path } },
        { name: parallel.name, source: { source: 'github', repo: parallel.repo } },
      ];
      if (args[1] === 'list') return { installed, available: [{ id: 'parallel@parallel-agent-skills', version: '0.12.0' }] };
      if (args[1] === 'update') installed[0].version = '2.0.0';
      if (args[1] === 'install') installed.push({ id: args[2], version: args[2].startsWith('parallel@') ? '0.12.0' : '1.0.0', enabled: true });
      if (args[1] === 'disable') installed.find((entry) => entry.id === args[2]).enabled = false;
      return {};
    },
  };
  return { runtime, calls };
}

test('AutoClaw audit reports package drift and missing installs without writing', async () => {
  const { runtime, calls } = fixture();
  const result = await syncAutoClawPlugins(runtime, [agenthub, parallel], base);
  assert.deepEqual(result.mappings.map(({ status }) => status), ['drift', 'missing', 'missing']);
  assert.equal(calls.length, 2);
});

test('AutoClaw applies native updates and installs with on-demand enablement, then converges', async () => {
  const { runtime } = fixture();
  const result = await syncAutoClawPlugins(runtime, [agenthub, parallel], base, { apply: true });
  assert.deepEqual(result.changes.map(({ action }) => action), ['update', 'install', 'disable', 'install']);
  assert.deepEqual(result.mappings.map(({ status, enabled }) => [status, enabled]), [
    ['current', false], ['current', false], ['current', true],
  ]);
  assert.deepEqual((await syncAutoClawPlugins(runtime, [agenthub, parallel], base, { apply: true })).changes, []);
});

test('AutoClaw apply refuses a conflicting source before refreshing any marketplace', async () => {
  const { runtime, calls } = fixture(resolve('some-other-marketplace'));
  await assert.rejects(syncAutoClawPlugins(runtime, [agenthub, parallel], base, { apply: true }), /different source owner/);
  assert.deepEqual(calls, [['plugins', 'marketplace', 'list']]);
});
