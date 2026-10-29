// Pure candidate-bound action/state review contract, shared by the release gate and tests.
const text = (value) => typeof value === 'string' && value.trim().length > 0;
const time = (value) => Number.isFinite(value) && value >= 0;
export function validateActionResultReview({job, storyboard, timeline, review, candidateSha256, candidateDurationSeconds}) {
  const errors = [];
  if (review?.mode === 'conceptual-animation') return validateConceptualAnimation({job, storyboard, timeline, review, candidateSha256, candidateDurationSeconds});
  if (review?.mode !== 'settled-state') {
    if (!Array.isArray(review?.events) || !review.events.length) return ['action-result review needs observed events.'];
    for (const event of review.events) {
      const times = [event?.actionAtSeconds, event?.resultVisibleAtSeconds, event?.spokenResultAtSeconds];
      if (!event?.segmentId || times.some((value) => !time(value))) errors.push('action-result event must include finite nonnegative action, visible-result, and spoken-result timing.');
      else if (event.resultVisibleAtSeconds < event.actionAtSeconds || event.spokenResultAtSeconds < event.resultVisibleAtSeconds) errors.push(`action-result event ${event.segmentId} announces a result before the picture proves it.`);
    }
    return errors;
  }
  if (!['explainer', 'teaser'].includes(job?.kind) || storyboard?.kind !== job.kind || job.noEnactedActions !== true || storyboard.noEnactedActions !== true) errors.push('settled-state review requires matching explainer or teaser kinds and explicit noEnactedActions=true in both job and storyboard.');
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

// A conceptual sequence has narration references, not fictional completed application results.
function validateConceptualAnimation({job, storyboard, timeline, review, candidateSha256, candidateDurationSeconds}) {
  const errors = [];
  for (const [name, declaration] of [['job', job], ['storyboard', storyboard]]) {
    if (declaration?.kind !== 'animation' || declaration.noEnactedActions !== true || declaration.noCompletedResultClaims !== true) errors.push(`conceptual-animation ${name} must declare animation, noEnactedActions=true and noCompletedResultClaims=true for the whole film.`);
  }
  if (review.status !== 'PASS' || !/^[a-f0-9]{64}$/.test(candidateSha256 ?? '') || review.candidateSha256 !== candidateSha256) errors.push('conceptual-animation review must be a PASS bound to the exact encoded candidate.');
  if (review.independent !== true || !text(review.reviewer) || !text(job?.producer) || review.reviewer.trim() === job.producer.trim()) errors.push('conceptual-animation requires an identified reviewer independent of the named producer.');
  if (review.noCompletedResultClaims !== true || !text(review.narrationAssessment)) errors.push('conceptual-animation requires explicit independent whole-film narration applicability assessment.');
  if (review.events !== undefined && (!Array.isArray(review.events) || review.events.length)) errors.push('conceptual-animation cannot contain enacted-action events.');
  if (!time(candidateDurationSeconds) || candidateDurationSeconds === 0) errors.push('conceptual-animation requires the measured encoded program duration.');
  const beats = storyboard?.beats, segments = timeline?.segments;
  if (!Array.isArray(beats) || !beats.length || !Array.isArray(segments) || !segments.length) return [...errors, 'conceptual-animation requires storyboard beats and the complete narration timeline.'];
  if (!Array.isArray(review.observedConcepts) || !review.observedConcepts.length) return [...errors, 'conceptual-animation requires concrete independent observations; no blanket exemption.'];
  const covered = new Set();
  for (const observation of review.observedConcepts) {
    const id = observation?.segmentId;
    const matchingBeats = beats.filter((beat) => beat?.id === id), matchingSegments = segments.filter((segment) => segment?.id === id);
    if (!text(id) || matchingBeats.length !== 1 || matchingSegments.length !== 1) { errors.push('conceptual-animation observation must identify one storyboard beat and matching narration segment.'); continue; }
    if (covered.has(id)) errors.push(`conceptual-animation observation ${id} is duplicated.`);
    covered.add(id);
    if (!text(matchingBeats[0].provesClaim) || !text(observation.concept) || !text(observation.evidence)) errors.push(`conceptual-animation observation ${id} needs a declared concept and concrete encoded-picture evidence.`);
    if (!['question', 'imperative', 'intent', 'context'].includes(observation.narrationRole) || !text(observation.narrationExcerpt) || !text(matchingSegments[0].text) || !matchingSegments[0].text.includes(observation.narrationExcerpt)) errors.push(`conceptual-animation observation ${id} needs an actual narration excerpt and non-completion role.`);
    const visible = observation.visibleAtSeconds, narration = observation.narrationAtSeconds;
    if (!time(visible) || !time(narration) || narration > candidateDurationSeconds || visible > narration) errors.push(`conceptual-animation observation ${id} needs finite in-program visual evidence before its narration reference.`);
    if (['actionAtSeconds', 'resultVisibleAtSeconds', 'spokenResultAtSeconds'].some((key) => Object.hasOwn(observation, key))) errors.push(`conceptual-animation observation ${id} must not invent action or completed-result clocks.`);
  }
  for (const item of [...beats, ...segments]) if (!text(item?.id) || !covered.has(item.id)) errors.push('conceptual-animation observations must cover every storyboard beat and narration segment.');
  return errors;
}
