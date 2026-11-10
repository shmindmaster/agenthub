import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, copyFileSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { check, seen, due, parseCsv, REGISTER } from '../skills/scout/scripts/register.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const fixtures = join(here, 'fixtures');
const script = join(here, '..', 'skills', 'scout', 'scripts', 'register.mjs');

function withBrokenRegister(edit, run) {
  const root = mkdtempSync(join(tmpdir(), 'funding-register-'));
  try {
    copyFileSync(join(fixtures, REGISTER), join(root, REGISTER));
    writeFileSync(join(root, REGISTER), edit(readFileSync(join(root, REGISTER), 'utf8')));
    run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('parseCsv keeps a quoted comma inside one cell', () => {
  assert.deepEqual(parseCsv('a,b\n"x, y",z\n'), [['a', 'b'], ['x, y', 'z']]);
});

test('check accepts the fixture register', () => {
  assert.deepEqual(check(fixtures), { rows: 3, problems: [] });
});

test('check reports a duplicate id, a bad date, a bad band and an unquoted comma', () => {
  withBrokenRegister(
    (text) => text
      .replace('EX-ACC-02', 'EX-GRANT-01')
      .replace(/2025-10-01\r?\n$/, 'last month\n')
      .replace(',P4,', ',P9,')
      .replace('"Up to $100,000"', 'Up to $100,000'),
    (root) => {
      const { problems } = check(root);
      for (const expected of ['duplicate id', 'verified must be', 'band must be', 'quote any value']) {
        assert.ok(problems.some((p) => p.includes(expected)), `missing problem: ${expected}\n${problems.join('\n')}`);
      }
    },
  );
});

test('check fails when a column is renamed', () => {
  withBrokenRegister((text) => text.replace('reopen_if', 'reopen'), (root) => {
    assert.ok(check(root).problems[0].startsWith('header differs'));
  });
});

test('seen finds a closed row by name and by URL, with its reopen condition', () => {
  for (const query of ['example accelerator', 'https://www.example.com/accelerator']) {
    const { register } = seen(fixtures, query);
    assert.equal(register.length, 1, query);
    assert.equal(register[0].closed, true);
    assert.equal(register[0].reopen_if, 'A paying customer exists');
  }
});

test('seen finds a program that only the narrative rejected list names', () => {
  const result = seen(fixtures, 'Example Cloud Credits');
  assert.equal(result.register.length, 0);
  assert.equal(result.notes.length, 1);
  assert.match(result.notes[0].text, /Declined/);
});

test('seen returns nothing for an unknown program', () => {
  const result = seen(fixtures, 'Entirely Unknown Fund');
  assert.deepEqual([result.register.length, result.notes.length], [0, 0]);
});

test('due lists open rows past the verification window and leaves closed rows out', () => {
  const stale = due(fixtures, 30, new Date('2026-01-20T00:00:00Z'));
  assert.deepEqual(stale.map((r) => r.id), ['EX-PRIZE-03']);
  const later = due(fixtures, 30, new Date('2026-06-01T00:00:00Z'));
  assert.deepEqual(later.map((r) => r.id), ['EX-GRANT-01', 'EX-PRIZE-03']);
});

test('the command exits 1 on a broken register and 2 when the register is missing', () => {
  assert.equal(spawnSync(process.execPath, [script, 'check', fixtures]).status, 0);
  withBrokenRegister((text) => text.replace(',P4,', ',P9,'), (root) => {
    assert.equal(spawnSync(process.execPath, [script, 'check', root]).status, 1);
  });
  const missing = spawnSync(process.execPath, [script, 'check', join(fixtures, 'absent')], { encoding: 'utf8' });
  assert.equal(missing.status, 2);
  assert.match(missing.stderr, /do not create a second register/);
});
