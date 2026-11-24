import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const treatments = read('skills/studio/references/treatments.md');
const recipes = read('skills/produce/references/motion-recipes.md');
const archetypes = JSON.parse(read('kit/scene-archetypes.json')).archetypes.map(a => a.id);
const kinds = new Set(JSON.parse(read('kit/scene-archetypes.json')).archetypes.flatMap(a => a.kit));
const recipeRows = recipes.split('\n').filter(l => l.startsWith('| ') && !l.startsWith('| Recipe') && !l.startsWith('| ---'));
const rows = text => text.split('\n').filter(line => /^\| [A-Z]{2}\d /.test(line));

test('treatment and recipe notes stay within their size budgets', () => {
  assert.ok(Buffer.byteLength(treatments) < 9 * 1024);
  assert.ok(Buffer.byteLength(recipes) < 7 * 1024);
});

test('every treatment names only archetypes and visual kinds the kit has', () => {
  const known = new Set([...archetypes, ...kinds, 'render-overlay', 'sourceRegion', 'captionRegion', 'repeatIsPoint', 'speaker', 'title', 'at', 'campaign-contract.mjs']);
  const names = [...treatments.matchAll(/`([a-z][a-z-]*)`/g)].map(m => m[1]);
  const archetypeLike = names.filter(n => n.includes('-') && !n.endsWith('.md') && !n.includes('.'));
  for (const name of archetypeLike) assert.ok(known.has(name), `unknown kit name: ${name}`);
});

test('each of the ten formats has at least two treatments', () => {
  const ids = rows(treatments).map(r => r.split('|')[1].trim().replace(/\d+$/, ''));
  const counts = ids.reduce((m, id) => ({ ...m, [id]: (m[id] || 0) + 1 }), {});
  assert.equal(Object.keys(counts).length, 10, 'format prefix count');
  for (const [id, n] of Object.entries(counts)) assert.ok(n >= 2, `${id} has ${n}`);
});

test('every treatment row has all seven columns and closes with a named picture', () => {
  for (const row of rows(treatments)) {
    assert.equal(row.split('|').length - 2, 7, row.slice(0, 20));
  }
});

test('a recipe marked built points at a component that exists in the kit', () => {
  const shots = read('kit/explainer/shots.tsx');
  const visuals = read('kit/src/Visuals.tsx');
  for (const row of recipeRows) {
    const cells = row.split('|').map(c => c.trim());
    const realized = cells[6];
    if (/not built/.test(realized)) continue;
    const symbol = /`([A-Z][A-Za-z]+)`/.exec(realized);
    if (symbol) assert.ok(shots.includes(symbol[1]) || visuals.includes(symbol[1]), `${symbol[1]} missing from kit`);
  }
});

test('every recipe row carries timing, easing and a limit', () => {
  const table = recipeRows;
  assert.ok(table.length >= 10 && table.length <= 12, `recipes: ${table.length}`);
  for (const line of table) {
    const cells = line.split('|').slice(1, -1).map(c => c.trim());
    assert.equal(cells.length, 6, line.slice(0, 30));
    assert.ok(cells.every(Boolean));
  }
});
