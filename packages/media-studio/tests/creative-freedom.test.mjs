import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkStory } from '../scripts/check-story.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';
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

test('an unbranded cut can select explainer truth rules and disclose its speculation', () => {
  const report = checkStory({
    conceptDisclosure: 'Illustrative scenario',
    cuts: [{ id: 'lesson', filmType: 'explainer', targetSeconds: 36,
      narrative: { question: 'What changes when outcomes are replaced?', viewerValue: 'Compare the two distributions' },
      beats: [
        { kind: 'broll', role: 'explanation', truthStatus: 'proposed', line: 'Imagine a second projection.' },
        { role: 'takeaway', line: 'Replacing the draw resets the distribution.' },
      ],
    }],
  });
  assert.equal(report.ok, true, JSON.stringify(report.cuts[0].failures));
});

test('a product from the brand file keeps the same truth rules as a product named in the brief', () => {
  const brief = (extra = {}) => ({
    conceptDisclosure: 'Illustrative scenario', ...extra,
    cuts: [{ id: 'lesson', filmType: 'explainer', targetSeconds: 36,
      narrative: { question: 'What changes when outcomes are replaced?', viewerValue: 'Compare the two distributions' },
      beats: [
        { kind: 'broll', role: 'explanation', truthStatus: 'proposed', line: 'Imagine a second projection.' },
        { role: 'takeaway', line: 'Replacing the draw resets the distribution.' },
      ],
    }],
  });
  const representation = (report) => report.cuts[0].failures.some((f) => f.rule === 'truth.representation');
  const inline = checkStory(brief({ product: 'Rexa' }));
  const viaBrand = checkStory(brief(), { product: 'Rexa' });
  const unbranded = checkStory(brief());
  assert.equal(representation(inline), true, 'a named product keeps verified-demo truth rules');
  assert.equal(representation(viaBrand), representation(inline), JSON.stringify(viaBrand.cuts[0].failures));
  assert.equal(viaBrand.creativeMode, inline.creativeMode);
  assert.equal(representation(unbranded), false, JSON.stringify(unbranded.cuts[0].failures));
  assert.equal(checkStory(brief({ creativeMode: 'concept-film' }), { product: 'Rexa' }).cuts[0].failures.some((f) => f.rule === 'truth.representation'), false,
    'an explicit creative mode stays authoritative');
});

test('the closed job schema allows explicit illustrative release declarations', () => {
  const schema = JSON.parse(readFileSync(new URL('../schemas/job.schema.json', import.meta.url), 'utf8'));
  const job = { kind: 'explainer', title: 'Independent draws', workspace: '/job', repositoryWritePolicy: 'read-only',
    noEnactedActions: true, noCompletedResultClaims: true };
  assert.deepEqual(validate(schema, job), []);
  assert.notDeepEqual(validate(schema, { ...job, noCompletedResultClaims: 'true' }), []);
});
