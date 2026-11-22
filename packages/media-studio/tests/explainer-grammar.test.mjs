// The grammar's job is to make the declared archetype matter. The old kit
// declared 22 archetypes and the renderer read one; these tests fail if that
// regresses, and they pin the composition families the storyboard relies on.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  ARCHETYPE_FAMILY,
  FAMILIES,
  RULES,
  allowedArchetypes,
  familyOf,
  familySpec,
  kindsOf,
  validateFilm,
  validateShot,
} from '../kit/explainer/grammar.mjs';
import { layoutFor } from '../kit/explainer/layout.mjs';

const catalogue = JSON.parse(readFileSync(new URL('../kit/scene-archetypes.json', import.meta.url), 'utf8'));

test('every archetype in the catalogue renders as a real family', () => {
  const declared = catalogue.archetypes.map((entry) => entry.id);
  assert.ok(declared.length >= 16, 'the catalogue keeps at least 16 archetypes');
  for (const id of declared) {
    assert.ok(familyOf(id), `${id} has no composition family`);
    assert.ok(FAMILIES[familyOf(id)], `${id} maps to an unknown family`);
  }
  assert.deepEqual(new Set(allowedArchetypes()), new Set(declared), 'the grammar and the catalogue name the same archetypes');
});

test('the archetypes the fleet storyboards already use keep their meaning', () => {
  assert.equal(familyOf('cold-open'), 'statement');
  assert.equal(familyOf('diagram-build'), 'mechanism');
  assert.equal(familyOf('drawn-mechanism'), 'mechanism');
  assert.equal(familyOf('before-after'), 'contrast');
  assert.equal(familyOf('kinetic-number'), 'number');
  assert.equal(familyOf('evidence-proof'), 'evidence');
  assert.equal(familyOf('checklist-build'), 'checklist');
  assert.equal(familyOf('chapter-card'), 'chapter');
  assert.equal(familyOf('cta-end-frame'), 'end');
  assert.equal(familyOf('quote-problem'), 'quote');
});

test('each family declares the picture it needs and the size rung it composes at', () => {
  for (const [name, spec] of Object.entries(FAMILIES)) {
    assert.ok(Array.isArray(spec.kinds), `${name} needs a kinds list`);
    assert.ok(['xl', 'l', 'm', 's'].includes(spec.tier), `${name} needs a tier`);
    assert.ok(spec.maxBeats >= 1 && spec.maxBeats <= 12, `${name} needs a sane beat budget`);
    assert.ok(spec.cap > 0 && spec.cap <= 1, `${name} needs a film share cap`);
    assert.ok(spec.note.length > 20, `${name} needs a note that says what it is for`);
    const layout = layoutFor(name);
    assert.ok(layout.hero, `${name} needs a hero region`);
  }
});

test('a family refuses a visual kind it cannot compose', () => {
  const problems = validateShot({ id: 'x', archetype: 'kinetic-number', title: 'n', visual: { kind: 'code', lines: [] } });
  assert.ok(problems.some((problem) => problem.rule === 'visual-kind'), JSON.stringify(problems));
  const missing = validateShot({ id: 'x', archetype: 'diagram-build', title: 'n' });
  assert.ok(missing.some((problem) => problem.rule === 'visual-required'));
});

test('an unknown archetype fails instead of falling back to a slide', () => {
  const problems = validateShot({ id: 'x', archetype: 'talking-paper', title: 'n' });
  assert.deepEqual(problems.map((problem) => problem.rule), ['archetype-known']);
});

test('a beat budget is enforced per family', () => {
  const beats = Array.from({ length: 4 }, (_, index) => ({ target: `w${index}`, atSeconds: index }));
  const problems = validateShot({ id: 'x', archetype: 'kinetic-statement', title: 'n', beats });
  assert.ok(problems.some((problem) => problem.rule === 'beat-budget'));
});

test('a shot repeats the previous family only when the repeat is the point', () => {
  const shot = { id: 'x', archetype: 'kinetic-statement', title: 'n', durationSeconds: 4 };
  assert.ok(validateShot(shot, { previousFamily: 'statement' }).some((p) => p.rule === 'no-consecutive-repeat'));
  assert.deepEqual(validateShot({ ...shot, repeatIsPoint: true }, { previousFamily: 'statement' }), []);
});

test('a shot longer than the ceiling needs a reason, and one under the floor never passes', () => {
  const base = { id: 'x', archetype: 'kinetic-statement', title: 'n' };
  assert.ok(validateShot({ ...base, durationSeconds: 0.9 }, {}).some((p) => p.rule === 'shot-min'));
  assert.ok(validateShot({ ...base, durationSeconds: 13 }, {}).some((p) => p.rule === 'shot-max'));
  assert.deepEqual(
    validateShot({ ...base, durationSeconds: 13, longShotReason: 'one continuous build over a long take' }, {}),
    [],
  );
});

test('a film of type-only frames is refused', () => {
  const shots = [
    { id: 'a', archetype: 'kinetic-statement', title: 'one', durationSeconds: 4 },
    { id: 'b', archetype: 'cold-open', title: 'two', durationSeconds: 4 },
    { id: 'c', archetype: 'kinetic-number', title: 'three', visual: { kind: 'stat', value: '1', label: 'x' }, durationSeconds: 4 },
    { id: 'd', archetype: 'quote-problem', title: 'four', visual: { kind: 'quote', text: 'q' }, durationSeconds: 4 },
  ];
  const problems = validateFilm(shots);
  assert.ok(problems.some((problem) => problem.rule === 'type-only-cap'));
});

test('the family catalogue is specific enough to vary the frame', () => {
  const kinds = Object.values(FAMILIES).map((spec) => spec.tier);
  assert.ok(kinds.filter((tier) => tier === 'xl').length >= 3, 'several families can carry a full frame');
  assert.ok(new Set(Object.values(FAMILIES).map((spec) => spec.light)).size >= 3, 'light is not one setting');
  assert.equal(kindsOf('mechanism').includes('flow'), true);
  assert.equal(RULES.maxStaticRunSeconds, 2.5);
  assert.equal(RULES.minHoldSeconds, 1.0);
  assert.ok(familySpec('evidence').tier === 'm');
});
