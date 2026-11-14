# Workflow detail

## Red flags

| Thought | Reality |
| --- | --- |
| "I'll write the script and fix the picture later." | The picture shapes the script. Beat sheet first, with a picture per beat. |
| "The status tool is bureaucracy." | It is the only thing that tells the next session what is true. |
| "They said 'sounds good' earlier, I'll approve." | Approval is for the exact thing, in this conversation, recorded by the command. |
| "A text card is quicker." | Quick and empty is the failure this studio exists to prevent. |

## Pace

Do the free phases fast and in one go: develop and pre-production need no spend. Pause for the two approvals (screenplay, plan), then run production and post without stopping unless a gate fails or spend would exceed the plan. Report at the end with the file, the gates that ran, the gates that did not, and the cost against the estimate.

## The phases

| Phase | Deliverables | Skill | Owner approves |
| --- | --- | --- | --- |
| 1 Develop: idea to script | `case/case.md`, `story/treatment.md`, `story/beat-sheet.json`, `story/screenplay.json`, narration check | `brief`, `develop` | the case, then the screenplay |
| 2 Pre-production: plan and design | `story/picture-plan.json`, `story/storyboard.json`, `story/visual-bible.json`, `plan/breakdown.json` (cast, assets, budget, schedule), relevance and variety gates | `plan`, `visuals` | the plan: picture table and cost |
| 3 Production: make the parts | voice takes, assets (drawn, generated, captured), cue sheet, built props, rendered picture | `generate`, `visuals`, `capture`, `compose` | none, unless spend rises |
| 4 Post: assemble and check | finished file, loudness, word sync, frame integrity, the review verdict | `compose`, `review` | none |
| 5 Delivery | captions sidecar, library copy, delivered record | `compose` | delivery |

Read `references/phases.md` for what each phase means for each kind of piece, and how light a phase can be.


## Start

```text
py -3 scripts/studio_init.py "<working title>" --kind <briefing|explainer|training|documentary|animation|teaser|...> --identity <mahumtech|abacare>
py -3 scripts/production_status.py <jobRoot>        # where it stands and what to do next, at any time
```

`production_status.py` is the memory of the job. Run it first in every session that touches a production, and after every step. It names the phase, the failing check and the next skill. Never claim a phase is done that it does not show as PASS.
