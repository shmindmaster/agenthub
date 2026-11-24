import test from 'node:test';
import assert from 'node:assert/strict';
import { checkStory } from '../scripts/check-story.mjs';
import { judge } from '../kit/explainer/validate-explainer-release.mjs';
import { build, cueSheet } from './fixtures/explainer/fixture.mjs';

test('the brief selects education with code and synthetic math pictures', () => {
  const report = checkStory({
    filmType: 'tutorial', creativeMode: 'educational', targetSeconds: 60,
    narrative: { goal: 'Compute a probability by counting outcomes' },
    beats: [
      { role: 'goal', line: 'Count the winning outcomes.' },
      { role: 'step', visualMode: 'screen', truthStatus: 'illustrative', line: 'Use a synthetic Python grid.' },
      { role: 'payoff', line: 'Divide the winning count by the grid size.' },
    ],
  });
  assert.equal(report.cuts[0].filmType, 'tutorial');
  assert.equal(report.ok, true, JSON.stringify(report.cuts[0].failures));
});

test('fiction can open on an invented world without a product arc or emotional template', () => {
  const report = checkStory({
    filmType: 'story', targetSeconds: 45,
    beats: [{ kind: 'broll', truthStatus: 'fictional', line: 'The moon slowly unfolds into an origami city.' }],
  });
  assert.equal(report.creativeMode, 'fictional-story');
  assert.equal(report.ok, true, JSON.stringify(report.cuts[0].failures));
});

test('an abstract probability explanation may open directly on an example', () => {
  const report = checkStory({
    filmType: 'explainer', targetSeconds: 35,
    narrative: { question: 'What makes draws independent?', viewerValue: 'Predict the next draw' },
    beats: [
      { role: 'explanation', line: 'A blue marble lands on the table.' },
      { role: 'takeaway', line: 'Replacing it resets the distribution.' },
    ],
  });
  assert.equal(report.ok, true, JSON.stringify(report.cuts[0].failures));
});

test('purposeful reading time survives strict encoded review, while receipt binding still fails closed', () => {
  const props = build().props;
  const metrics = { propsSha256: 'A', film: { longestStaticSeconds: 8 } };
  const verdict = judge({ props, propsSha256: 'A', cueSheet, metrics, strict: true });
  assert.equal(verdict.ok, true, JSON.stringify(verdict.failed));
  assert.ok(verdict.advisories.some(({ rule }) => rule === 'static-run'));
  assert.equal(judge({ props, propsSha256: 'B', cueSheet, metrics }).ok, false);
});

test('fabricated capture cannot be presented as deployed success inside an explainer', () => {
  const report = checkStory({
    product: 'Rexa', filmType: 'explainer', creativeMode: 'explainer', targetSeconds: 30,
    beats: [{ kind: 'ui', truthStatus: 'illustrative', line: 'Rexa deployed this successfully.' }],
    storyOverrides: [{ rule: 'truth.representation', reason: 'The made-up evidence looks plausible.' }],
  });
  assert.ok(report.cuts[0].failures.some(({ rule }) => rule === 'truth.representation'));
});
