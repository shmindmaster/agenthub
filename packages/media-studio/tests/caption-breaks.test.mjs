import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chunkWords } from '../kit/marketing/lib/captions.mjs';
import { captionCues } from '../scripts/picture-gates.mjs';

// Aligner words with no punctuation and a long pause before the next scene (the 3.1.2 proof film, cue 3).
const at = (list, start, step = 0.3) => list.split(' ').map((word, i) => ({ word, start: start + i * step, end: start + i * step + 0.25 }));
const words = [...at('brings your clinic\'s at-risk work into one view', 5.3), ...at('Open any authorization to see its evidence', 10.38)];

test('a pause ends a cue even without punctuation', () => {
  const chunks = chunkWords(words, { maxCps: 20 });
  assert.ok(chunks.every((c) => !(c.text.includes('view') && c.text.includes('Open'))), JSON.stringify(chunks.map((c) => c.text)));
});

test('a scene boundary ends a cue when there is no pause', () => {
  const tight = [...at('one two three', 1), ...at('four five six', 1.9)];
  const chunks = chunkWords(tight, { maxCps: 20, boundaries: [1.9] });
  assert.deepEqual(chunks.map((c) => c.text), ['one two three', 'four five six']);
});

test('captionCues reports a word shown long before it is spoken', () => {
  const slow = at('a b c d', 0, 1.5);
  const { early } = captionCues(slow);
  assert.equal(early.length, 0, 'gaps of 1.25 s are pauses and split the cue');
  const { early: none } = captionCues(words);
  assert.deepEqual(none, []);
});
