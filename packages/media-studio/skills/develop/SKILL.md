---
name: develop
description: Develops an approved case into a logline, treatment, beat sheet with a picture per beat, and a locked screenplay written for the ear. Use when a film has a case and needs its story, script, scenes and narrative. Not before a brief exists; use brief. Not for the picture plan; use plan.
---

# Develop

## Workflow contract

1. Use the approved case, stated promise and source material.
2. Draft the logline, treatment, beat sheet and screenplay in order, then run the gates and record approval.
3. Hand `plan` the locked screenplay, beat sheet and approved story decision.
4. If a beat lacks a defensible picture or approval, revise the beat before planning.

Turn the case into the form that the viewer actually requested. Read
`../video/references/creative-formats.md` before choosing a structure.
A current-product demo uses a factual problem/action/result sequence;
a fictional day-in-the-life may follow characters, a documentary can
build from sourced evidence, and a future vision may begin with an
invented full-resolution UI, family or patient scene. Abstract and
music-led works do not require one hero scene, a linear obstacle or
a strictly timed spoken hook. All people and synthetic screens may
look fully realistic; no default blurring or adult-only requirement.
Verified factual claims remain sourced while envisioned scenes are
free to be imaginative.

## Order

```text
- [ ] 1. Logline and concept check
- [ ] 2. Treatment (case/story/treatment.md)
- [ ] 3. Beat sheet with a picture per beat (story/beat-sheet.json)
- [ ] 4. Screenplay: locked lines per scene (story/screenplay.json)
- [ ] 5. Names pinned, narration check passes
- [ ] 6. Owner approves the case and the screenplay
```

## 5 Gates

```text
node scripts/check-story.mjs story/brief.json                  # the story has the parts its film type needs
py -3 scripts/check_script_terms.py story/locked-script.txt     # every name, acronym and brand decided
node scripts/validate-narration.mjs <jobRoot>                   # fluff, repeats, hook inside five seconds
```

Pin each name in `scripts/pronunciation_lexicon.json` before any voice is generated. Fix the lines, not the thresholds.

## 6 Approval

Show the owner the logline, the beat sheet table (beat, role, picture) and the first and last lines. When they say yes, record it: `py -3 scripts/production_status.py <jobRoot> --approve case` and `--approve screenplay`. Then `plan`.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)

For a consulting demo, technical walkthrough or product update, load [consulting communication](../video/references/consulting-communication.md). Write actionTitle conclusions first, attach supportingArgument, proofRefs, scoped claims and uiProof, then run check-story on the brief. Review its titlesOnly output at Pink; lock the argument and visible proof before narration or recapture.
