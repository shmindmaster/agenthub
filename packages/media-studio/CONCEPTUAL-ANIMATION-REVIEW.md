# Conceptual animation review

This explicit mode applies only to actual conceptual animation, without enacted application actions or narrated completed application results anywhere in the candidate. It does not replace workflow timing review. All other encoded-film gates remain required.

Both job.json and story/storyboard.json declare kind="animation", noEnactedActions=true and noCompletedResultClaims=true. The job names its producer. Every storyboard beat has an id matching exactly one narration-timeline segment and a provesClaim describing its concept.

The actionResultReview declares mode="conceptual-animation", status="PASS", the exact candidateSha256, independent=true, a named reviewer different from the producer, noCompletedResultClaims=true, and a concrete whole-film narrationAssessment. The reviewer must actually review the encoded film. Omit events or use an empty array.

observedConcepts covers every storyboard beat and every narration segment exactly once. Each item includes segmentId, concept, concrete encoded-picture evidence, an actual narrationExcerpt from that segment, narrationRole (question, imperative, intent or context), visibleAtSeconds and narrationAtSeconds. Both timestamps are finite, nonnegative and inside the measured encoded duration; visual evidence precedes or coincides with its narration reference. Do not fabricate actionAtSeconds, resultVisibleAtSeconds or spokenResultAtSeconds.

Questions, instructions and intent are conceptual references, not completed-result claims. If the film actually enacts a workflow or asserts its completed result, use the appropriate action/result contract rather than relabeling the film or inventing observations.

## Recorded settled-state teasers

A short marketing hook retains kind="teaser" in both job and storyboard. When its film uses recorded settled product states and conceptual diagrams without enacted actions, use mode="settled-state", not a whole-film conceptual-animation declaration. Both job and storyboard must declare noEnactedActions=true. An independent exact-candidate PASS must observe every storyboard beat against its matching narration segment, with a concrete state, encoded-picture evidence, resultVisibleAtSeconds and spokenResultAtSeconds inside the measured program, picture proof preceding the claim. Statements about existing recorded states require actual visible proof; a format label is not proof. Do not invent action times or omit beats.

This permits the teaser format under the existing settled-state evidence requirements; it does not permit an enacted workflow to avoid action/result review. The conceptual-animation mode remains restricted to whole-film animation with its stronger explicit no-completed-result applicability declaration. Marketing, picture, sound, narration and sync gates still apply.
