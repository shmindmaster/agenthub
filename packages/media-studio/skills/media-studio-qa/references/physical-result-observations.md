# Encoded result onset observations

`build-cue-sheet.mjs <jobRoot> --physical-results qa/physical-result-observations.json`
accepts optional independent frame review of the **final encoded candidate**.
It corrects conservative capture polling timestamps; it cannot change input-action
timestamps, voice clocks, thresholds, or waive enacted-action checks. Rebuild the
cue sheet after the final encode and run `validate-sync.mjs` on that exact file.

Schema `media-studio/physical-result-observations/1` requires `producer` and
`reviewer: { identity, independent: true, method }` with different identities.
All artifact references are job-relative `{path,sha256}`. Bind `candidate` and
`inputs: {receipt,composeMap,cuePlan}` to the current artifacts. `frameRate` is
`{numerator:30,denominator:1}` for a 30fps CFR candidate; its probed frame count,
dimensions and rational rate control validation.

Each nonempty `observations` item supplies `beat`, `clip`,
`receiptExpectationIndex`, exact cue result `label`, `firstVisibleFrame` (zero
based), `previousFrame` (exactly first minus one), encoded-pixel
`region:{x,y,w,h}`, distinct `previousState` and `visibleState`, and
`previousEvidence` / `visibleEvidence` references, each with its explicit `frame`.
These must be unannotated native PNG crops, with integer region coordinates.
The helper decodes each candidate frame using
`select=eq(n\,FRAME),crop=W:H:X:Y:exact=1,format=rgba` and compares its RGBA
pixels exactly with the decoded evidence image. Labeled contact sheets can be
supplementary review evidence, but cannot replace those pixel-bound crops.
Review actual neighboring frames to identify the first visible named state.
Saving, cleared form, enabled Submit, and saved success are different states;
an earlier intermediate state cannot prove the later spoken result. Do not
backfill or modify capture receipts. Copy evidence into the production workspace.

The builder retains raw receipt clock `clip_time` and mapped `poll_visible_at`,
and adds sidecar/frame/raw-poll provenance. The gate rechecks every binding,
frame clock, event identity, viewport region and cue override. Invalid declared
evidence fails closed. The physical onset remains a transition for freeze and
hold checks. Omitted sidecars preserve the existing receipt-based behavior.

Artifact hashes establish identity, not semantic image interpretation. The
identified independent reviewer must actually inspect the evidence against the
exact candidate; this contract is not automated recognition or human approval.
