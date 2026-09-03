# Scene archetype library

Canonical ids live in `kit/scene-archetypes.json`. This file is how the director and storyboard pick them.

The house Remotion kit is this library, not one briefing slide repeated. Composition `Briefing` still renders the program; each beat sets `visualArchetype`.

## Pick by story purpose

| Archetype | Use when | Kit visual |
| --- | --- | --- |
| `cold-open` | First 5–8s; image or statement before context | `statement` or `broll` |
| `full-bleed-broll` | Problem, outcome, or place — not product UI | `broll` / `still` |
| `kinetic-statement` | One sentence is the picture | empty bullets → Statement card |
| `kinetic-number` | One number worth remembering | `stat` |
| `before-after` | Old way vs new way | `beforeafter` |
| `comparison` | Two options, two costs | `split` |
| `diagram-build` | Structure that must arrive in order | `flow` / `layers` / `map` |
| `timeline` | Sequence over time | `timeline` |
| `process-flow` | Request path, pipeline | `flow` / `sequence` |
| `screen-in-context` | Real product in a designed frame | `screen-in-context` + capture plate |
| `talking-head-sidecar` | Face plus one claim | `sidecar` |
| `quote-problem` | The viewer's own objection | `quote` |
| `evidence-proof` | Receipt, table, cited fact | `proof` / `table` / `code` |
| `checklist-build` | Steps the viewer will steal | `checklist` |
| `hero-reveal` | The one protected payoff | `hero` |
| `cta-end-frame` | Designed last frame, one next step | `cta` |
| `chapter-card` | Webcast/webinar section break | `chapter` |
| `lower-third` | Speaker identification | `lower-third` |
| `speaker-slide` | Face plus a claim or slide | `sidecar` |

## Rules

1. Choose the **simplest truthful visual that maintains attention**. A cheaper still that holds across two ideas fails.
2. Do not use the same archetype on consecutive beats unless the repetition is the point (checklist build, diagram continuation via `revealFrom`).
3. Viewer-facing `briefing`, `training`, `explainer`, and `series-episode` must use this kit (Remotion) unless `intent: draft` or the user asked for a basic/proxy cut.
4. `screen` / live product still goes through `media-studio-capture`. Do not fake product UI inside an archetype.
5. A slide that does not build is unfinished — same rule as `engagement.md`.
