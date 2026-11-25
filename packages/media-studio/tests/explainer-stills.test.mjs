// The stills command picks frames and says which of them were caught mid-move.
// The picking and the sheet are pure, so they are tested without a browser.
import test from 'node:test';
import assert from 'node:assert/strict';
import { contactSheet, movingAt, pickFrames } from '../kit/explainer/still-explainer.mjs';
import { decodePng, encodePng } from '../kit/explainer/png.mjs';
import { build } from './fixtures/explainer/fixture.mjs';

const props = build().props;

test('the default is one settled opening and one hold per shot, in film order', () => {
  const frames = pickFrames(props);
  assert.equal(frames.length, props.shots.length * 2);
  assert.deepEqual(frames.map((still) => still.frame), [...frames.map((still) => still.frame)].sort((a, b) => a - b));
  for (const shot of props.shots) {
    const own = frames.filter((still) => still.shot === shot.id);
    assert.deepEqual(own.map((still) => still.moment), ['open', 'hold']);
    for (const still of own) assert.ok(still.frame >= shot.startFrame && still.frame < shot.startFrame + shot.durationFrames);
    assert.deepEqual(own[1].moving, [], `${shot.id} is settled at its hold`);
  }
});

test('beats are drawn after their entrance and before the next one', () => {
  const shot = props.shots[1];
  const beats = pickFrames(props, { shots: ['b'], moments: ['beats'] });
  assert.equal(beats.length, shot.beats.length);
  beats.forEach((still, i) => {
    const local = still.frame - shot.startFrame;
    assert.ok(local >= shot.beats[i].frame);
    if (shot.beats[i + 1]) assert.ok(local < shot.beats[i + 1].frame);
  });
});

test('a frame inside an entrance names what is moving', () => {
  const shot = props.shots[1];
  assert.deepEqual(movingAt(shot, 0, 30), ['opening']);
  assert.deepEqual(movingAt(shot, shot.beats[0].frame + 5, 30), [shot.beats[0].target]);
  assert.deepEqual(movingAt(shot, shot.durationFrames - 2, 30), []);
});

test('an opening line that lands word by word is settled only after its last word', () => {
  const shot = { id: 's', family: 'statement', title: 'one two three four five six seven', startFrame: 0, durationFrames: 120, beats: [] };
  assert.deepEqual(movingAt(shot, 40, 30), ['opening']);
  const [open] = pickFrames({ film: { fps: 30 }, shots: [shot] }, { moments: ['open'] });
  assert.ok(open.frame > 40);
  assert.deepEqual(open.moving, []);
});

test('a wrong shot or moment is refused by name', () => {
  assert.throws(() => pickFrames(props, { shots: ['zz'] }), /no shot zz/);
  assert.throws(() => pickFrames(props, { moments: ['middle'] }), /unknown moment middle/);
});

test('a frame that two moments share is drawn once', () => {
  const short = { film: { fps: 30 }, shots: [{ id: 's', family: 'statement', startFrame: 0, durationFrames: 20, beats: [] }] };
  const frames = pickFrames(short, { moments: ['open', 'hold'] });
  assert.deepEqual(frames.map((still) => still.frame), [18, 19]);
  assert.equal(new Set(frames.map((still) => still.frame)).size, frames.length);
});

test('the sheet frames a moving tile in red and a settled one in grey', () => {
  const image = (value) => {
    const rgba = Buffer.alloc(16 * 10 * 4, 255);
    for (let i = 0; i < rgba.length; i += 4) rgba.fill(value, i, i + 3);
    return { width: 16, height: 10, rgba };
  };
  const sheet = contactSheet([[{ image: image(10), moving: true }, { image: image(200), moving: false }], [{ image: image(90), moving: false }]], { tileWidth: 8, border: 2, gap: 4 });
  const at = (x, y) => [...sheet.rgba.subarray((y * sheet.width + x) * 4, (y * sheet.width + x) * 4 + 3)];
  assert.equal(sheet.width, 2 * (8 + 4 + 4) + 4);
  assert.deepEqual(at(4, 4), [232, 93, 93]);
  assert.deepEqual(at(4 + 2, 4 + 2), [10, 10, 10]);
  assert.deepEqual(at(4 + 16, 4), [70, 70, 70]);
  const read = decodePng(encodePng(sheet));
  assert.equal(read.width, sheet.width);
});
