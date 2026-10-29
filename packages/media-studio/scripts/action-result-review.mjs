// Pure candidate-bound action/state review contract, shared by the release gate and tests.
const text = (value) => typeof value === 'string' && value.trim().length > 0;
const time = (value) => Number.isFinite(value) && value >= 0;
export function validateActionResultReview({job, storyboard, timeline, review, candidateSha256, candidateDurationSeconds}) {
  const errors = [];
  if (review?.mode !== 'settled-state') {
    if (!Array.isArray(review?.events) || !review.events.length) return ['action-result review needs observed events.'];
    for (const event of review.events) {
      const times = [event?.actionAtSeconds, event?.resultVisibleAtSeconds, event?.spokenResultAtSeconds];
      if (!event?.segmentId || times.some((value) => !time(value))) errors.push('action-result event must include finite nonnegative action, visible-result, and spoken-result timing.');
      else if (event.resultVisibleAtSeconds < event.actionAtSeconds || event.spokenResultAtSeconds < event.resultVisibleAtSeconds) errors.push(`action-result event ${event.segmentId} announces a result before the picture proves it.`);
    }
    return errors;
  }
  if (job?.kind !== 'explainer' || job.noEnactedActions !== true || storyboard?.kind !== 'explainer' || storyboard.noEnactedActions !== true) errors.push('settled-state review requires an explainer and explicit noEnactedActions=true in both job and storyboard.');
  if (review.status !== 'PASS' || !/^[a-f0-9]{64}$/.test(candidateSha256 ?? '') || review.candidateSha256 !== candidateSha256) errors.push('settled-state review must be a PASS bound to the exact encoded candidate.');
  if (review.independent !== true || !text(review.reviewer)) errors.push('settled-state review requires an identified independent reviewer.');
  if (review.events !== undefined && (!Array.isArray(review.events) || review.events.length)) errors.push('settled-state review cannot contain enacted-action events.');
  const beats = storyboard?.beats;
  const segments = timeline?.segments;
  if (!Array.isArray(beats) || !beats.length || !Array.isArray(segments) || !segments.length) return [...errors, 'settled-state review requires storyboard beats and a narration timeline.'];
  const required = beats;
  if (beats.some((beat) => !text(beat?.id) || !text(beat?.provesClaim))) errors.push('settled-state storyboard must identify the claim each beat proves.');
  if (!time(candidateDurationSeconds) || candidateDurationSeconds === 0) errors.push('settled-state review requires the measured encoded program duration.');
  if (!Array.isArray(review.observedStates) || !review.observedStates.length) return [...errors, 'settled-state review needs independently observed states; no blanket skip.'];
  const covered = new Set();
  for (const observation of review.observedStates) {
    const id = observation?.segmentId;
    const matchingBeats = beats.filter((beat) => beat?.id === id);
    const matchingSegments = segments.filter((segment) => segment?.id === id);
    if (!text(id) || matchingBeats.length !== 1 || matchingSegments.length !== 1) { errors.push('settled-state observation must identify one storyboard beat and matching narration segment.'); continue; }
    const visible = observation.resultVisibleAtSeconds, spoken = observation.spokenResultAtSeconds;
    if (!time(visible) || !time(spoken) || spoken > candidateDurationSeconds || spoken < visible) errors.push(`settled-state observation ${id} needs finite in-program visible proof before its spoken claim.`);
    if (covered.has(id)) errors.push(`settled-state observation ${id} is duplicated.`);
    if (!text(observation.state) || !text(observation.evidence)) errors.push(`settled-state observation ${id} needs the observed state and concrete encoded-picture evidence.`);
    if (Object.hasOwn(observation, 'actionAtSeconds')) errors.push(`settled-state observation ${id} must not invent an enacted-action time.`);
    covered.add(id);
  }
  for (const beat of required) if (!covered.has(beat?.id)) errors.push(`settled-state review is missing the proof for storyboard beat ${beat?.id ?? "<invalid>"}.`);
  return errors;
}
