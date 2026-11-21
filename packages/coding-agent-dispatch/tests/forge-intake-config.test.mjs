import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const LAUNCHER = /^\.local\/bin\/[A-Za-z0-9][A-Za-z0-9._-]*$/;
const REPO = /^[^/\s]+\/[^/\s]+$/;
const PHASES = ['select', 'claim', 'implement', 'finish'];
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const isString = (value) => typeof value === 'string' && value.length > 0;
const isStrings = (value) => Array.isArray(value) && value.length > 0 && value.every(isString);

export function validateIntakeConfig(config) {
  const errors = [];
  if (!isObject(config)) return ['forge-intake.json must be a JSON object'];
  if (config.version !== 1) errors.push('version must be 1');

  const linear = config.linear;
  if (!isObject(linear)) errors.push('linear must be an object');
  else {
    for (const key of ['claimLabel', 'claimedState', 'reviewState', 'mcpUrl']) {
      if (!isString(linear[key])) errors.push(`linear.${key} must be a non-empty string`);
    }
    for (const key of ['pickStates', 'includeLabelsAny', 'excludeLabelPatterns']) {
      if (!isStrings(linear[key])) errors.push(`linear.${key} must be a non-empty string array`);
    }
    if (!Array.isArray(linear.excludeLabelPatterns) || !linear.excludeLabelPatterns.includes('agent:*')) {
      errors.push('linear.excludeLabelPatterns must include agent:*');
    }
    const tools = linear.toolsByPhase;
    if (!isObject(tools)) errors.push('linear.toolsByPhase must be an object');
    else {
      for (const phase of PHASES) {
        if (!isStrings(tools[phase])) errors.push(`linear.toolsByPhase.${phase} must be a non-empty string array`);
      }
      for (const phase of ['select', 'implement']) {
        if (isStrings(tools[phase])) {
          for (const tool of tools[phase].filter((name) => /^(save|create|update|delete)_/.test(name))) {
            errors.push(`linear.toolsByPhase.${phase} must not include ${tool}`);
          }
        }
      }
      for (const [phase, names] of Object.entries(tools)) {
        if (isStrings(names)) {
          for (const tool of names.filter((name) => name.startsWith('delete_'))) {
            errors.push(`linear.toolsByPhase.${phase} must not include delete tool ${tool}`);
          }
        }
      }
    }
  }

  const repos = config.repos;
  if (!isObject(repos) || Object.keys(repos).length === 0) errors.push('repos must be a non-empty object');
  else {
    for (const [key, entry] of Object.entries(repos)) {
      if (!key.startsWith('app:')) errors.push(`${key}: repo key must start with app:`);
      if (!isObject(entry)) {
        errors.push(`${key}: repo entry must be an object`);
        continue;
      }
      if (!isString(entry.repo) || !REPO.test(entry.repo)) errors.push(`${key}: repo must be an owner/name string`);
      if (!isString(entry.base)) errors.push(`${key}: base must be a non-empty string`);
      if (!isStrings(entry.protectedPaths)) errors.push(`${key}: protectedPaths must be a non-empty string array`);
      else {
        for (const path of ['.github/', 'registry/']) {
          if (!entry.protectedPaths.includes(path)) errors.push(`${key}: protectedPaths must include ${path}`);
        }
      }
    }
  }

  const limits = config.limits;
  if (!isObject(limits)) errors.push('limits must be an object');
  else {
    for (const [key, value] of Object.entries(limits)) {
      if (!Number.isInteger(value) || value <= 0) errors.push(`limits.${key} must be a positive integer`);
    }
    if (!Number.isInteger(limits.maxAttemptsPerIssue) || limits.maxAttemptsPerIssue <= 0) {
      errors.push('limits.maxAttemptsPerIssue must be a positive integer');
    } else if (limits.maxAttemptsPerIssue > 5) {
      errors.push('limits.maxAttemptsPerIssue must be at most 5');
    }
  }

  if (!Array.isArray(config.routes)) errors.push('routes must be an array');
  else {
    const ids = new Set();
    config.routes.forEach((route, index) => {
      const label = isString(route?.id) ? route.id : `route ${index}`;
      if (!isObject(route)) {
        errors.push(`${label}: route must be an object`);
        return;
      }
      if (!isString(route.id)) errors.push(`${label}: id must be a non-empty string`);
      else if (ids.has(route.id)) errors.push(`${route.id}: route id appears more than once`);
      else ids.add(route.id);
      if (!isString(route.launcher) || !LAUNCHER.test(route.launcher)) errors.push(`${label}: launcher must be a relative path under .local/bin/`);
      if (!isString(route.plan)) errors.push(`${label}: plan must be a non-empty string`);
      if (typeof route.enabled !== 'boolean') errors.push(`${label}: enabled must be a boolean`);
    });
    if (!config.routes.some((route) => isObject(route) && route.enabled === true)) errors.push('at least one route must be enabled');
  }
  return errors;
}

const configPath = fileURLToPath(new URL('../skills/dispatch/forge-intake.json', import.meta.url));
const config = JSON.parse(readFileSync(configPath, 'utf8'));
const invalid = (change, expected) => {
  const errors = validateIntakeConfig(structuredClone({ ...config, ...change }));
  assert.ok(errors.includes(expected), `expected ${JSON.stringify(expected)}, got ${JSON.stringify(errors)}`);
};

test('committed forge-intake.json passes validation', () => {
  assert.deepEqual(validateIntakeConfig(config), []);
});

test('every intake config rule can fail', () => {
  const validRepo = config.repos['app:agenthub'];
  const validRoute = config.routes[0];
  const limitsWithoutAttempts = { ...config.limits };
  delete limitsWithoutAttempts.maxAttemptsPerIssue;
  const linear = (key, value) => ({ linear: { ...config.linear, [key]: value } });
  const repo = (key, value) => ({ repos: { 'app:agenthub': { ...validRepo, [key]: value } } });
  const route = (key, value) => ({ routes: [{ ...validRoute, [key]: value }] });
  const cases = [
    ['root', { version: 1 }, undefined],
    ['version', { version: 2 }, 'version must be 1'],
    ['claim label', linear('claimLabel', ''), 'linear.claimLabel must be a non-empty string'],
    ['claimed state', linear('claimedState', ''), 'linear.claimedState must be a non-empty string'],
    ['review state', linear('reviewState', ''), 'linear.reviewState must be a non-empty string'],
    ['mcp url', linear('mcpUrl', ''), 'linear.mcpUrl must be a non-empty string'],
    ['pick states', linear('pickStates', []), 'linear.pickStates must be a non-empty string array'],
    ['include labels', linear('includeLabelsAny', []), 'linear.includeLabelsAny must be a non-empty string array'],
    ['agent claim exclusion', linear('excludeLabelPatterns', config.linear.excludeLabelPatterns.filter((pattern) => pattern !== 'agent:*')), 'linear.excludeLabelPatterns must include agent:*'],
    ['select tools', linear('toolsByPhase', { ...config.linear.toolsByPhase, select: [] }), 'linear.toolsByPhase.select must be a non-empty string array'],
    ['selector write', linear('toolsByPhase', { ...config.linear.toolsByPhase, select: ['save_issue'] }), 'linear.toolsByPhase.select must not include save_issue'],
    ['claim tools', linear('toolsByPhase', { ...config.linear.toolsByPhase, claim: [] }), 'linear.toolsByPhase.claim must be a non-empty string array'],
    ['implement tools', linear('toolsByPhase', { ...config.linear.toolsByPhase, implement: [] }), 'linear.toolsByPhase.implement must be a non-empty string array'],
    ['finish tools', linear('toolsByPhase', { ...config.linear.toolsByPhase, finish: [] }), 'linear.toolsByPhase.finish must be a non-empty string array'],
    ['implement save_issue', linear('toolsByPhase', { ...config.linear.toolsByPhase, implement: [...config.linear.toolsByPhase.implement, 'save_issue'] }), 'linear.toolsByPhase.implement must not include save_issue'],
    ['implement save_comment', linear('toolsByPhase', { ...config.linear.toolsByPhase, implement: [...config.linear.toolsByPhase.implement, 'save_comment'] }), 'linear.toolsByPhase.implement must not include save_comment'],
    ['delete tool', linear('toolsByPhase', { ...config.linear.toolsByPhase, finish: [...config.linear.toolsByPhase.finish, 'delete_issue'] }), 'linear.toolsByPhase.finish must not include delete tool delete_issue'],
    ['repos', { repos: {} }, 'repos must be a non-empty object'],
    ['repo key', { repos: { agenthub: validRepo } }, 'agenthub: repo key must start with app:'],
    ['owner/name', repo('repo', 'agenthub'), 'app:agenthub: repo must be an owner/name string'],
    ['base', repo('base', ''), 'app:agenthub: base must be a non-empty string'],
    ['protected paths', repo('protectedPaths', []), 'app:agenthub: protectedPaths must be a non-empty string array'],
    ['github protection', repo('protectedPaths', validRepo.protectedPaths.filter((path) => path !== '.github/')), 'app:agenthub: protectedPaths must include .github/'],
    ['registry protection', repo('protectedPaths', validRepo.protectedPaths.filter((path) => path !== 'registry/')), 'app:agenthub: protectedPaths must include registry/'],
    ['zero limit', { limits: { ...config.limits, maxFiles: 0 } }, 'limits.maxFiles must be a positive integer'],
    ['fractional limit', { limits: { ...config.limits, maxFiles: 1.5 } }, 'limits.maxFiles must be a positive integer'],
    ['missing attempt limit', { limits: limitsWithoutAttempts }, 'limits.maxAttemptsPerIssue must be a positive integer'],
    ['attempt cap', { limits: { ...config.limits, maxAttemptsPerIssue: 6 } }, 'limits.maxAttemptsPerIssue must be at most 5'],
    ['duplicate route id', { routes: [...config.routes, { ...validRoute }] }, 'codex-zai: route id appears more than once'],
    ['route id', route('id', ''), 'route 0: id must be a non-empty string'],
    ['absolute launcher', route('launcher', '/usr/local/bin/x'), 'codex-zai: launcher must be a relative path under .local/bin/'],
    ['outside launcher', route('launcher', 'bin/x'), 'codex-zai: launcher must be a relative path under .local/bin/'],
    ['escaping launcher', route('launcher', '.local/bin/../x'), 'codex-zai: launcher must be a relative path under .local/bin/'],
    ['plan', route('plan', ''), 'codex-zai: plan must be a non-empty string'],
    ['enabled type', route('enabled', 'yes'), 'codex-zai: enabled must be a boolean'],
    ['no enabled route', { routes: config.routes.map((item) => ({ ...item, enabled: false })) }, 'at least one route must be enabled'],
  ];
  for (const [name, change, expected] of cases) {
    if (name === 'root') assert.deepEqual(validateIntakeConfig([]), ['forge-intake.json must be a JSON object']);
    else invalid(change, expected);
  }
});
