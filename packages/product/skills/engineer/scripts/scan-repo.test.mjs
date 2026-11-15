import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scan, isSource, isTest, missingConfigs, detectStacks } from './scan-repo.mjs';

const big = 'x\n'.repeat(1600);
const mid = 'x\n'.repeat(900);
const syntheticKey = 'AKIA' + 'ABCDEFGHIJKLMNOP';
const files = {
  'package.json': '{}',
  'src/app/service.ts': big,
  'src/app/view.tsx': mid,
  'src/app/small.ts': '// TODO one\n// FIXME two\n',
  'src/app/other.ts': 'ok',
  'src/app/more.ts': 'ok',
  'dist/bundle.js': big,
  'db/migrations/001.py': big,
  'tests/service.test.ts': big,
  '.env': 'A=1',
  '.env.example': 'A=',
  'src/keys.ts': `const k = "${syntheticKey}";`,
};
const r = scan('fixture', () => Object.keys(files), (p) => files[p]);

test('flags large source files at warn and fail thresholds, skipping generated, migrations and tests', () => {
  assert.deepEqual(r.largeFiles.map((l) => [l.file, l.level]), [['src/app/service.ts', 'fail'], ['src/app/view.tsx', 'warn']]);
});

test('counts markers and reports committed env files and secret-shaped strings without values', () => {
  assert.equal(r.markers, 2);
  assert.deepEqual(r.committedEnvFiles, ['.env']);
  assert.deepEqual(r.secretShapedFiles, ['src/keys.ts']);
  assert.ok(!JSON.stringify(r).includes(syntheticKey));
});

test('reports missing JS lint and format config, and accepts biome for both', () => {
  assert.ok(r.missingConfigs.some((m) => m.startsWith('JS/TS linter')));
  const withBiome = ['package.json', 'biome.json'];
  assert.deepEqual(missingConfigs(withBiome, detectStacks(withBiome), () => ''), []);
});

test('accepts ruff and mypy declared in pyproject', () => {
  const f = ['pyproject.toml'];
  assert.deepEqual(missingConfigs(f, detectStacks(f), () => '[tool.ruff]\n[tool.mypy]\n'), []);
});

test('classifies sources and tests', () => {
  assert.ok(isSource('src/a.ts') && !isSource('src/a.d.ts') && !isSource('node_modules/x/a.js'));
  assert.ok(isTest('tests/a.ts') && isTest('src/a.spec.tsx') && isTest('pkg/test_a.py') && !isTest('src/latest.ts'));
});

test('lists source directories with no nearby tests', () => {
  assert.deepEqual(r.untestedDirs.map((u) => u.dir), ['src/app']);
});
