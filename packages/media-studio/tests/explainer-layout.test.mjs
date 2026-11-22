// Layout is computed, not measured in the DOM, so it can be tested without a
// browser. These tests protect the two things that made the old board feel the
// same in every scene: one hero box for every family, and a headline that never
// reflows after it appears.
import test from 'node:test';
import assert from 'node:assert/strict';
import { FAMILIES } from '../kit/explainer/grammar.mjs';
import { aspectOf, fitHeadline, isWide, layoutFor, textWidth, wrapText } from '../kit/explainer/layout.mjs';
import { theme } from '../kit/explainer/theme.mjs';

const canvas = { width: 1600, height: 1000 };

test('every family composes inside the canvas and below the top chrome', () => {
  for (const family of Object.keys(FAMILIES)) {
    const layout = layoutFor(family, canvas);
    for (const key of ['hero', 'kicker', 'title', 'sub']) {
      const box = layout[key];
      if (!box) continue;
      assert.ok(box.x >= 0 && box.y >= 0, `${family}.${key} starts outside the frame`);
      assert.ok(box.x + box.w <= canvas.width + 1, `${family}.${key} runs past the right edge`);
      assert.ok(box.y + box.h <= canvas.height + 1, `${family}.${key} runs past the bottom edge`);
    }
  }
});

test('the families do not share one layout', () => {
  const statement = layoutFor('statement', canvas);
  const evidence = layoutFor('evidence', canvas);
  const mechanism = layoutFor('mechanism', canvas);
  assert.notDeepEqual(statement.hero, evidence.hero);
  assert.ok(mechanism.hero.w > evidence.hero.w, 'a mechanism bleeds wider than an evidence card');
  assert.ok(statement.hero.h > evidence.hero.h, 'a statement is taller than a proof block');
  assert.equal(statement.kicker, null, 'a statement has no kicker row');
  assert.ok(evidence.title.y < evidence.hero.y, 'the claim sits above its evidence');
  assert.ok(evidence.title.y + evidence.title.h <= evidence.hero.y, 'the claim and the evidence never overlap');
});

test('a full-bleed family owns the whole frame', () => {
  const media = layoutFor('media', canvas);
  assert.deepEqual(media.hero, { x: 0, y: 0, w: 1600, h: 1000, align: 'left', valign: 'bottom' });
});

test('the layout is landscape-only and says so', () => {
  assert.throws(() => layoutFor('statement', { width: 1080, height: 1920 }), /landscape-only/);
  assert.equal(isWide({ width: 1920, height: 1080 }), true);
  assert.equal(aspectOf({ width: 1600, height: 1000 }), 1.6);
});

test('a headline shrinks until it fits its lines and never exceeds its width', () => {
  const box = layoutFor('statement', canvas).hero;
  const long = 'One revision lands overnight and every commitment becomes a question';
  const fitted = fitHeadline(long, { maxWidth: box.w, maxLines: 3, maxSize: theme.type.xl, minSize: 72 });
  assert.ok(fitted.lines.length <= 3);
  assert.ok(fitted.size <= theme.type.xl && fitted.size >= 72);
  for (const line of fitted.lines) {
    assert.ok(textWidth(line, fitted.size, theme.type.tracking.display) <= box.w + 1, `"${line}" overflows at ${fitted.size}px`);
  }
  assert.equal(fitted.overflow, false);
});

test('a short headline keeps the largest size', () => {
  const fitted = fitHeadline('One revision.', { maxWidth: 1360, maxLines: 3, maxSize: 168, minSize: 72 });
  assert.equal(fitted.size, 168);
  assert.equal(fitted.lines.length, 1);
});

test('an impossible headline reports overflow instead of silently clipping', () => {
  const fitted = fitHeadline('supercalifragilisticexpialidocious '.repeat(20), { maxWidth: 300, maxLines: 1, maxSize: 168, minSize: 120 });
  assert.equal(fitted.overflow, true);
  assert.equal(fitted.lines.length, 1);
});

test('wrapping is greedy and stable, and width grows with size', () => {
  const lines = wrapText('alpha beta gamma delta', 200, 40);
  assert.ok(lines.length >= 2);
  assert.equal(lines.join(' '), 'alpha beta gamma delta');
  assert.ok(textWidth('alpha beta', 40) > textWidth('alpha beta', 20));
});

test('the safe area keeps the type clear of the progress bar', () => {
  const { safe } = layoutFor('statement', canvas);
  assert.ok(safe.y >= 90, 'the top chrome needs room');
  assert.ok(safe.y + safe.h <= canvas.height - 100, 'nothing readable sits under the progress bar');
});
