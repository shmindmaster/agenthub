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
