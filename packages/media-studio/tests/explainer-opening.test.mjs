// A shot made of words opens on them. A late anchor on its visual must not leave
// the frame empty until the word is spoken.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(new URL('../kit/explainer/shots.tsx', import.meta.url), 'utf8');
const body = (name) => {
  const start = source.indexOf(`const ${name}: FC<ShotProps>`);
  assert.ok(start >= 0, name);
  const end = source.indexOf(': FC<ShotProps>', start + name.length + 20);
  return source.slice(start, end < 0 ? undefined : end);
};

test('words-only shots open at the start, not at their first beat', () => {
  for (const name of ['Statement', 'QuoteShot', 'MediaShot', 'ChapterShot', 'EndShot']) {
    assert.ok(body(name).includes('const at = openingAt(fps);'), name);
    assert.ok(!body(name).includes('beatAt('), name);
  }
});

test('a number waits for its word inside furniture that is already up', () => {
  assert.ok(body('NumberShot').includes('const open = openingAt(fps);'));
});

test('a sting waits for its word only when it is drawn', () => {
  assert.ok(body('StingShot').includes("visual.kind === 'lottie' ? beatAt(shot, fps) : openingAt(fps)"));
});
