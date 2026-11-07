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

Turn the case into a story and then into locked lines. This is where the idea becomes something worth watching. Quality here is what no later step can add back.

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
py -3 scripts/check_script_terms.py story/locked-script.txt     # every name, acronym and brand decided
node scripts/validate-narration.mjs <jobRoot>                   # fluff, repeats, hook inside five seconds
```

Pin each name in `scripts/pronunciation_lexicon.json` before any voice is generated. Fix the lines, not the thresholds.

## 6 Approval

Show the owner the logline, the beat sheet table (beat, role, picture) and the first and last lines. When they say yes, record it: `py -3 scripts/production_status.py <jobRoot> --approve case` and `--approve screenplay`. Then `plan`.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
