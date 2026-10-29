import test from 'node:test';
import assert from 'node:assert/strict';
import { validateActionResultReview as validate } from '../scripts/action-result-review.mjs';

const sha = 'a'.repeat(64);
function fixture() {
  return {
    candidateSha256: sha, candidateDurationSeconds: 12,
    job: { kind: 'explainer', noEnactedActions: true },
    storyboard: { kind: 'explainer', noEnactedActions: true, beats: [
      { id: 'assessment', provesClaim: 'Assessment and acknowledgement are distinct.' },
      { id: 'authorization', provesClaim: 'Authorization is separately recorded.' },
    ] },
    timeline: { segments: [{ id: 'assessment', startSeconds: 0, durationSeconds: 5 }, { id: 'authorization', startSeconds: 5, durationSeconds: 5 }] },
    review: { mode: 'settled-state', status: 'PASS', candidateSha256: sha, independent: true, reviewer: 'Independent encoded-film reviewer', observedStates: [
      { segmentId: 'assessment', state: 'Two distinct status cards are visible.', evidence: 'Encoded frame at 1.0s shows separate acknowledgement and assessment labels.', resultVisibleAtSeconds: 1, spokenResultAtSeconds: 2 },
      { segmentId: 'authorization', state: 'Authorization is recorded separately.', evidence: 'Encoded frame at 6.0s shows the separate authorization card.', resultVisibleAtSeconds: 6, spokenResultAtSeconds: 7 },
    ] },
  };
}
test('explicit independently observed settled-state explainer passes', () => assert.deepEqual(validate(fixture()), []));
test('retimed proof may fall outside its original narration segment but inside the encoded program', () => {
  const f = fixture(); Object.assign(f.review.observedStates[1], { resultVisibleAtSeconds: 10, spokenResultAtSeconds: 11 });
  assert.deepEqual(validate(f), []);
});
const invalid = {
  'product screencast cannot opt into settled states': f => { f.job.kind = 'product-screencast'; },
  'job declaration is required': f => { delete f.job.noEnactedActions; },
  'storyboard declaration is required': f => { delete f.storyboard.noEnactedActions; },
  'storyboard must also be an explainer': f => { f.storyboard.kind = 'product-screencast'; },
  'exact candidate binding is required': f => { f.review.candidateSha256 = 'b'.repeat(64); },
  'candidate SHA must be a SHA256': f => { f.candidateSha256 = f.review.candidateSha256 = 'invalid'; },
  'failed review cannot release': f => { f.review.status = 'FAIL'; },
  'independence must be explicit': f => { f.review.independent = false; },
  'reviewer must be named': f => { f.review.reviewer = ' '; },
  'blanket skip is rejected': f => { f.review.observedStates = []; },
  'all storyboard beats require proof': f => { f.review.observedStates.pop(); },
  'malformed storyboard beat fails closed': f => { f.storyboard.beats.push(null); },
  'every beat requires an explicit claim': f => { delete f.storyboard.beats[1].provesClaim; },
  'unknown segments are rejected': f => { f.review.observedStates[1].segmentId = 'unknown'; },
  'timeline correspondence is required': f => { f.timeline.segments.pop(); },
  'duplicate timeline ids are ambiguous': f => { f.timeline.segments.push(f.timeline.segments[0]); },
  'duplicate observations are rejected': f => { f.review.observedStates.push(f.review.observedStates[0]); },
  'concrete picture evidence is required': f => { f.review.observedStates[0].evidence = ''; },
  'observed state is required': f => { f.review.observedStates[0].state = ''; },
  'invented action times are rejected': f => { f.review.observedStates[0].actionAtSeconds = 0; },
  'mixed enacted events are rejected': f => { f.review.events = [{ segmentId: 'assessment' }]; },
  'spoken claim cannot precede visible proof': f => { f.review.observedStates[0].spokenResultAtSeconds = 0.5; },
  'negative timestamps are rejected': f => { f.review.observedStates[0].resultVisibleAtSeconds = -1; },
  'nonfinite timestamps are rejected': f => { f.review.observedStates[0].spokenResultAtSeconds = NaN; },
  'numeric strings are rejected': f => { f.review.observedStates[0].resultVisibleAtSeconds = '1'; },
  'proof outside encoded program is rejected': f => { f.review.observedStates[1].spokenResultAtSeconds = 13; },
  'encoded program duration must be measured': f => { delete f.candidateDurationSeconds; },
  'infinite program duration is rejected': f => { f.candidateDurationSeconds = Infinity; },
};
for (const [name, mutate] of Object.entries(invalid)) test(name, () => { const f = fixture(); mutate(f); assert.ok(validate(f).length > 0); });
test('default enacted action remains valid with action-before-picture-before-speech', () => {
  assert.deepEqual(validate({ review: { events: [{ segmentId: 'click', actionAtSeconds: 1, resultVisibleAtSeconds: 2, spokenResultAtSeconds: 3 }] } }), []);
});
test('settled observations alone do not bypass default enacted-action review', () => {
  const f = fixture(); delete f.review.mode; assert.ok(validate(f).length > 0);
});
test('default enacted action still rejects speech before result', () => {
  assert.ok(validate({ review: { events: [{ segmentId: 'click', actionAtSeconds: 1, resultVisibleAtSeconds: 3, spokenResultAtSeconds: 2 }] } }).length > 0);
});
test('default enacted action still rejects nonfinite action time', () => {
  assert.ok(validate({ review: { events: [{ segmentId: 'click', actionAtSeconds: Infinity, resultVisibleAtSeconds: 3, spokenResultAtSeconds: 4 }] } }).length > 0);
});

function conceptualFixture() {
  return {
    candidateSha256: sha, candidateDurationSeconds: 12,
    job: { kind: 'animation', producer: 'film-producer', noEnactedActions: true, noCompletedResultClaims: true },
    storyboard: { kind: 'animation', noEnactedActions: true, noCompletedResultClaims: true, beats: [{ id: 'question', provesClaim: 'Source traceability is the question.' }, { id: 'intent', provesClaim: 'Retaining sources is the intended workflow.' }] },
    timeline: { segments: [{ id: 'question', text: 'What connects the numbers to their source?' }, { id: 'intent', text: 'Retain the source. The intent is traceability.' }] },
    review: { mode: 'conceptual-animation', status: 'PASS', candidateSha256: sha, independent: true, reviewer: 'independent-reviewer', noCompletedResultClaims: true, narrationAssessment: 'Reviewed the whole encoded film: the opening poses a question and the closing describes intent, without asserting completed application results.', observedConcepts: [
      { segmentId: 'question', concept: 'Source and number diagram', evidence: 'At 1s the source card connects to a number card.', narrationRole: 'question', narrationExcerpt: 'What connects the numbers', visibleAtSeconds: 1, narrationAtSeconds: 2 },
      { segmentId: 'intent', concept: 'Intended source retention', evidence: 'At 6s a source card remains connected to its record.', narrationRole: 'imperative', narrationExcerpt: 'Retain the source.', visibleAtSeconds: 6, narrationAtSeconds: 7 },
    ] },
  };
}
test('explicit conceptual animation uses actual concepts and narration references without invented results', () => assert.deepEqual(validate(conceptualFixture()), []));
const invalidConcepts = {
  'animation alone is not an exemption': f => { delete f.job.noEnactedActions; },
  'whole-film result declaration is required': f => { delete f.storyboard.noCompletedResultClaims; },
  'enacted screencast cannot opt in': f => { f.job.kind = 'product-screencast'; },
  'storyboard cannot relabel the film': f => { f.storyboard.kind = 'explainer'; },
  'wrong candidate is rejected': f => { f.review.candidateSha256 = 'b'.repeat(64); },
  'failed review rejected': f => { f.review.status = 'FAIL'; },
  'self review rejected': f => { f.review.reviewer = f.job.producer; },
  'unnamed producer rejected': f => { delete f.job.producer; },
  'independence required': f => { f.review.independent = false; },
  'whole-film narration assessment required': f => { delete f.review.narrationAssessment; },
  'reviewer must assess no completed claims': f => { f.review.noCompletedResultClaims = false; },
  'empty observations rejected': f => { f.review.observedConcepts = []; },
  'uncovered narration rejected': f => { f.timeline.segments.push({ id: 'unreviewed', text: 'Additional claim.' }); },
  'uncovered storyboard rejected': f => { f.storyboard.beats.push({ id: 'unreviewed' }); },
  'duplicate observations rejected': f => { f.review.observedConcepts.push(f.review.observedConcepts[0]); },
  'ambiguous segments rejected': f => { f.timeline.segments.push(f.timeline.segments[0]); },
  'completed-result role rejected': f => { f.review.observedConcepts[0].narrationRole = 'completed-result'; },
  'invented narration excerpt rejected': f => { f.review.observedConcepts[0].narrationExcerpt = 'The export completed.'; },
  'concrete picture evidence required': f => { f.review.observedConcepts[0].evidence = ''; },
  'concept required': f => { f.review.observedConcepts[0].concept = ''; },
  'declared concept required': f => { delete f.storyboard.beats[0].provesClaim; },
  'invented result clock rejected': f => { f.review.observedConcepts[0].resultVisibleAtSeconds = 1; },
  'enacted events rejected': f => { f.review.events = [{ segmentId: 'question' }]; },
  'nonfinite times rejected': f => { f.review.observedConcepts[0].narrationAtSeconds = NaN; },
  'negative times rejected': f => { f.review.observedConcepts[0].visibleAtSeconds = -1; },
  'out of program times rejected': f => { f.review.observedConcepts[0].narrationAtSeconds = 13; },
  'visual after narration rejected': f => { f.review.observedConcepts[0].visibleAtSeconds = 3; },
  'missing measured duration rejected': f => { delete f.candidateDurationSeconds; },
  'default action rule still applies without explicit mode': f => { delete f.review.mode; },
};
for (const [name, mutate] of Object.entries(invalidConcepts)) test(`conceptual-animation: ${name}`, () => { const f = conceptualFixture(); mutate(f); assert.ok(validate(f).length > 0); });

// A teaser is a format, not permission to invent enacted application actions.
function teaserFixture() {
  const f = fixture(); f.job.kind = f.storyboard.kind = 'teaser'; return f;
}
test('settled-state teaser retains its honest format and concrete per-beat proof', () => assert.deepEqual(validate(teaserFixture()), []));
for (const [name, mutate] of Object.entries(invalid)) test(`settled-state teaser: ${name}`, () => { const f = teaserFixture(); mutate(f); assert.ok(validate(f).length > 0); });
test('settled-state teaser cannot mix storyboard classification', () => {
  const f = teaserFixture(); f.storyboard.kind = 'explainer'; assert.ok(validate(f).length > 0);
});
test('settled-state explainer cannot relabel its storyboard as teaser', () => {
  const f = fixture(); f.storyboard.kind = 'teaser'; assert.ok(validate(f).length > 0);
});
test('teaser classification does not establish whole-film conceptual animation', () => {
  const f = conceptualFixture(); f.job.kind = f.storyboard.kind = 'teaser'; assert.ok(validate(f).length > 0);
});
