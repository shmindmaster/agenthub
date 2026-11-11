---
name: review
description: Decides whether an encoded candidate ships, with a score, defects and the scenes to revise. Use when someone asks to review, score, QA or verify a cut, check sync or ask if a film is ready. Not for fixing it; use compose or capture.
---

# Review

## Workflow contract

1. Use the exact encoded candidate, associated plan, receipts and audience goal.
2. Inspect the candidate and evidence, grade it, and name the earliest stage that owns any defect.
3. Return the ship verdict, defects, repair target and candidate identity.
4. If evidence is missing or bound to another candidate, block delivery and request a fresh review after repair.

Judge the exact encoded file, not the proxy, the screenplay or the render log. Gate on defects, not on whether it rendered. Never say sync or visual quality is verified from a PASS report alone: inspect the rendered file and its audio, and name every check not performed. You do not edit media.

Evaluate the **film that was actually requested**, using `video/references/creative-formats.md`. For a verified current-product marketing demo, enforce fast audience orientation, factual evidence, purposeful cursor and no redundant product-tour narration. For fictional drama, documentary, concept/vision, abstract, musical or educational work, do **not** ban repetition as an artistic technique, dialog about synthetic worlds, invented characters, patient/child scenes, imagined UI, slow openings or non-linear storytelling. The finished candidate is still subject to honest representation, legibility, craft and requested outcome. A source-evidence gate applies to verified current claims, not to explicitly speculative scenes.

## Output and loop

Write `qa/story-experience-review.json` per `schemas/story-experience-review.schema.json`: `score`, findings with location, evidence, fix and `owner`, and `reviseSceneIds`. `pass` is true only when `status` is `COMPLETE`, the score meets `craftScoreMin`, and no finding blocks.

On a fail, the owner reruns only those scenes, re-encodes, and review reruns. Do not restart writer, capture or TTS. Deliver only on a pass; a recut voids every candidate-bound report.

Example: a slow-middle cut gives `score: 78, pass: false, reviseSceneIds: ["s4","s7"], findings[0].owner: "video"`, not "Looks pretty good."

## References

- `references/gates.md`: Read when running release gates or confirming pronunciation.
- `references/word-clocks.md`: Read when aligning or defending a word clock.
- `references/story-review-rubric.md`: Read when scoring or judging a film.
- `references/marketing-readiness.md`: Read when reviewing a marketing cut.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)

For consulting profiles, load [consulting communication](../video/references/consulting-communication.md). Use Go/No-Go, Pink, Red and Gold as stage names in the existing consolidated review. Judge titles-only coherence, proof scope, screen comprehension, the actual first-15-second answer, voice joins and captions in the intended player. Record stage, timestamp, scene, owner and repair in findings; misleading claims or unreadable key results block regardless of score.
