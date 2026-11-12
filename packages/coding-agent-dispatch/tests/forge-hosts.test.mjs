import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const HOST_ID = /^[a-z0-9][a-z0-9-]*$/;

// A `-zai`, `-qwen`, `-go` or `-mimo` suffix is a plan route: the plan field
// must name the matching subscription so a launcher cannot be filed under the
// wrong plan.
const PLAN_SUFFIXES = [
  ['-zai', /z\.ai/i],
  ['-qwen', /qwen/i],
  ['-go', /opencode go/i],
  ['-mimo', /mimo/i],
];

// forge-session.py resolves argv[0] against the runner home, so it must stay
// a relative path with no way to walk out of it.
const LAUNCHER = /^\.local\/bin\/[A-Za-z0-9][A-Za-z0-9._-]*$/;
// The single catalog exception: grok's official installer owns .grok/bin/,
// and the hard-coded sign-in guidance in Invoke-CodingAgent.ps1 points there.
const GROK_LAUNCHER = /^\.grok\/bin\/[A-Za-z0-9][A-Za-z0-9._-]*$/;

// JSON.parse keeps only the last of two equal keys, so a duplicate host id would
// silently replace the earlier launcher. Scan the raw text for repeated keys at
// the top level of the catalog object.
export function duplicateHostIds(text) {
  const seen = new Set();
  const duplicates = new Set();
  let depth = 0;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (char === '"') {
      let end = i + 1;
      while (end < text.length && text[end] !== '"') end += text[end] === '\\' ? 2 : 1;
      if (depth === 1) {
        let next = end + 1;
        while (/\s/.test(text[next] ?? '')) next += 1;
        if (text[next] === ':') {
          const key = JSON.parse(text.slice(i, end + 1));
          if (seen.has(key)) duplicates.add(key);
          seen.add(key);
        }
      }
      i = end;
    } else if (char === '{' || char === '[') {
      depth += 1;
    } else if (char === '}' || char === ']') {
      depth -= 1;
    }
  }
  return [...duplicates];
}

export function validateForgeHosts(text) {
  const errors = [];
  let catalog;
  try {
    catalog = JSON.parse(text);
  } catch (error) {
    return [`forge-hosts.json does not parse as JSON: ${error.message}`];
  }
  if (catalog === null || typeof catalog !== 'object' || Array.isArray(catalog)) {
    return ['forge-hosts.json must be a JSON object'];
  }
  for (const id of duplicateHostIds(text)) errors.push(`${id}: host id appears more than once; JSON.parse would keep only the last entry`);
  const ids = Object.keys(catalog);
  if (ids.length === 0) errors.push('forge-hosts.json must list at least one host');
  for (const id of ids) {
    if (!HOST_ID.test(id)) errors.push(`${id}: host id must match ${HOST_ID}`);
    const route = catalog[id];
    if (route === null || typeof route !== 'object' || Array.isArray(route)) {
      errors.push(`${id}: entry must be an object with argv and optional plan`);
      continue;
    }
    // plan is optional: both consumers tolerate its absence. forge-session.py
    // reads only argv, and Invoke-CodingAgent.ps1 -Auth guards on
    // `if ($entry.Value.plan)`. Account sign-in routes (grok, kiro, qwen,
    // cline, ...) carry no plan by design.
    const keys = Object.keys(route);
    for (const key of keys) {
      if (key !== 'argv' && key !== 'plan') errors.push(`${id}: unexpected key ${key}; only argv and plan are allowed`);
    }
    const argv = route.argv;
    if (!Array.isArray(argv) || argv.length === 0 || argv.some((part) => typeof part !== 'string' || part.length === 0)) {
      errors.push(`${id}: argv must be a non-empty array of non-empty strings`);
    } else if (!(LAUNCHER.test(argv[0]) || (id === 'grok' && GROK_LAUNCHER.test(argv[0])))) {
      errors.push(`${id}: argv[0] must be a relative path under .local/bin/ with no .. segment and no leading slash`);
    }
    if ('plan' in route && (typeof route.plan !== 'string' || route.plan.length === 0)) {
      errors.push(`${id}: plan must be a non-empty string when present`);
    }
    for (const [suffix, pattern] of PLAN_SUFFIXES) {
      if (id.endsWith(suffix) && (typeof route.plan !== 'string' || !pattern.test(route.plan))) {
        errors.push(`${id}: id ending in ${suffix} must carry a plan naming the matching subscription (${pattern})`);
      }
    }
    // Claude and Codex never run on a personal login on Forge; every launcher
    // is a plan route, matching the refusal message in forge-session.py.
    if (id === 'claude' || id === 'codex') errors.push(`${id}: Claude and Codex ids must carry a plan suffix (-qwen, -zai, -mimo or -go)`);
  }
  return errors;
}

const catalogPath = fileURLToPath(new URL('../skills/dispatch/forge-hosts.json', import.meta.url));
const catalogText = readFileSync(catalogPath, 'utf8');
const valid = { ok: { argv: ['.local/bin/ok'], plan: 'Qwen Token Plan' } };

test('committed forge-hosts.json passes validation', () => {
  assert.deepEqual(validateForgeHosts(catalogText), []);
});

test('rule 1: the catalog parses as a JSON object with at least one host', () => {
  assert.ok(validateForgeHosts('{').some((error) => error.includes('does not parse')));
  assert.deepEqual(validateForgeHosts('[{"argv": [".local/bin/x"]}]'), ['forge-hosts.json must be a JSON object']);
  assert.deepEqual(validateForgeHosts('"ok"'), ['forge-hosts.json must be a JSON object']);
  assert.ok(validateForgeHosts('{}').some((error) => error.includes('at least one host')));
});

test('rule 1b: a host id may appear only once (checked on the raw text)', () => {
  const duplicated = '{"codex-go": {"argv": [".local/bin/a"], "plan": "OpenCode Go"}, "codex-go": {"argv": [".local/bin/b"], "plan": "OpenCode Go"}}';
  assert.deepEqual(JSON.parse(duplicated)['codex-go'].argv, ['.local/bin/b'], 'JSON.parse silently keeps the last entry');
  assert.deepEqual(duplicateHostIds(duplicated), ['codex-go']);
  assert.ok(validateForgeHosts(duplicated).some((error) => error.startsWith('codex-go: host id appears more than once')));
  // Keys nested inside an entry, and strings that merely look like keys, are not host ids.
  const nested = '{"a": {"argv": ["x"], "plan": "p"}, "b": {"argv": ["x"], "plan": "a\\": "}}';
  assert.deepEqual(duplicateHostIds(nested), []);
});

test('rule 2: every host id matches ^[a-z0-9][a-z0-9-]*$', () => {
  for (const id of ['Claude-zai', '-claude-zai', 'claude_zai', 'claude zai', 'claude.zai']) {
    const errors = validateForgeHosts(JSON.stringify({ ...valid, [id]: { argv: ['.local/bin/x'], plan: 'Z.ai Coding Plan' } }));
    assert.ok(errors.some((error) => error.includes('host id must match')), `${id} must be rejected`);
  }
});

test('rule 3: entries carry only argv and plan; argv is a non-empty array of non-empty strings; plan is a non-empty string when present', () => {
  const cases = [
    [{ argv: ['.local/bin/x'], model: 'glm' }, 'unexpected key model'],
    [{ plan: 'Qwen Token Plan' }, 'argv must be a non-empty array'],
    [{ argv: [] }, 'argv must be a non-empty array'],
    [{ argv: '.local/bin/x' }, 'argv must be a non-empty array'],
    [{ argv: ['.local/bin/x', ''] }, 'argv must be a non-empty array'],
    [{ argv: ['.local/bin/x'], plan: '' }, 'plan must be a non-empty string'],
    [{ argv: ['.local/bin/x'], plan: 7 }, 'plan must be a non-empty string'],
  ];
  for (const [route, message] of cases) {
    const errors = validateForgeHosts(JSON.stringify({ ...valid, bad: route }));
    assert.ok(errors.some((error) => error.startsWith(`bad: ${message}`)), `${JSON.stringify(route)} must fail with "${message}", got ${JSON.stringify(errors)}`);
  }
});

test('rule 4: argv[0] is a relative path under .local/bin/ with no .. segment and no leading slash', () => {
  for (const launcher of ['/usr/bin/x', '../bin/x', '.local/bin/../x', 'bin/x', '.local/bin/', '.local/bin']) {
    const errors = validateForgeHosts(JSON.stringify({ ...valid, bad: { argv: [launcher] } }));
    assert.ok(errors.some((error) => error.startsWith('bad: argv[0] must be a relative path')), `${launcher} must be rejected`);
  }
  // .grok/bin/ is the grok-only exception; any other host must use .local/bin/.
  const misplaced = validateForgeHosts(JSON.stringify({ ...valid, kiro: { argv: ['.grok/bin/kiro-cli'] } }));
  assert.ok(misplaced.some((error) => error.startsWith('kiro: argv[0] must be a relative path')), '.grok/bin/ outside grok must be rejected');
});

test('rule 5: -zai, -qwen, -go and -mimo ids carry a plan naming the matching subscription', () => {
  const cases = [
    ['claude-zai', { argv: ['.local/bin/x'] }, 'missing plan'],
    ['claude-zai', { argv: ['.local/bin/x'], plan: 'Qwen Token Plan' }, 'wrong plan'],
    ['codex-qwen', { argv: ['.local/bin/x'], plan: 'Z.ai Coding Plan' }, 'wrong plan'],
    ['codex-go', { argv: ['.local/bin/x'], plan: 'Z.ai Coding Plan' }, 'wrong plan'],
    ['claude-mimo', { argv: ['.local/bin/x'], plan: 'OpenCode Go' }, 'wrong plan'],
  ];
  for (const [id, route, why] of cases) {
    const errors = validateForgeHosts(JSON.stringify({ ...valid, [id]: route }));
    assert.ok(errors.some((error) => error.includes('must carry a plan naming the matching subscription')), `${id} with ${why} must be rejected`);
  }
});

test('rule 6: claude and codex ids always carry a plan suffix', () => {
  for (const id of ['claude', 'codex']) {
    const errors = validateForgeHosts(JSON.stringify({ ...valid, [id]: { argv: ['.local/bin/x'], plan: 'Z.ai Coding Plan' } }));
    assert.ok(errors.some((error) => error.includes('must carry a plan suffix')), `${id} without a plan suffix must be rejected`);
  }
});
