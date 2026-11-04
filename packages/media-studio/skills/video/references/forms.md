# Forms

Lookup for `programForm`, `kind`, `deliveryProfile`, series and campaigns in `job.json`. Infer them from the brief. One promise per film; organize around the viewer's job, not the product nav.

## Kinds

Remotion is required for every kind marked R, unless `intent: draft`. Draft is TTS plus stills; record what was skipped.

| `kind` | Use | `deliveryProfile` | Make it |
| --- | --- | --- | --- |
| `product-screencast` | Real UI | set per job | Product picture contract, `record-job.mjs`, `validate-product-picture.mjs` |
| `briefing` | Argument | `briefing-board` | R. Composition `Briefing` from the house kit. Exact logos, numbers, legal text are set type |
| `training` | One skill per clip, about 3 min | `onboarding` | R. Interrupt between cards |
| `explainer` | Idea, no live product | `youtube-16x9` | R. Diagram that builds |
| `talking-head` | Face carries it | `youtube-16x9` | Azure TTS avatar batch, `subtitleType: none`. Register change on the payoff |
| `animation` | Motion teaches | `youtube-16x9` | Accepted or Azure still, then Remotion. Exact diagrams are SVG |
| `audio-only` | Voice, bed | none | Silence on the key line |
| `series-episode` | Series | `youtube-16x9` | R. See Series |
| `webcast` | Broadcast | `webcast` | R. Speaker, slide, lower-third, chapters |
| `webinar` | Taught, Q&A | `webcast` | R. Real chapters |
| `keynote` | Speaker-led | `youtube-16x9` | R. Change angle |
| `documentary` | Picture-led | `youtube-16x9` | R. Slower voice, B-roll |
| `teaser` | 15-45s hook | `linkedin`; `vertical-9x16` for Shorts | R. Recut via `sourceJobId` |

## Program forms

Campaign forms are enforced by `job.schema.json`: `kind` `product-screencast`, explicit `deliveryProfile`, `job.campaign`.

| `programForm` | Promise | Length | Default `kind` |
| --- | --- | --- | --- |
| `hero` | Problem, solution, result | 30-60s | `product-screencast` |
| `product-overview` | Major workflows | 2-5 min | `product-screencast` |
| `outcome-workflow` | Pain, task, AI acts, human reviews, result | 1-3 min | `product-screencast` |
| `role-demo` | One persona's job | 2-5 min | `product-screencast` |
| `feature-tutorial` | One task as an outcome | 1-3 min | `product-screencast` |
| `customer-story` | Problem, workflow, evidence | 2-5 min | `documentary` |
| `before-after` | Old steps, new path | 30-90s | `product-screencast` |
| `ai-in-action` | Input, draft, concern, edit, save | 1-3 min | `product-screencast` |
| `ai-trust` | Data, controls, limits, approval | 2-5 min | `product-screencast` |
| `integration-demo` | With that system | 1-3 min | `product-screencast` |
| `onboarding` | First success | 2-5 min | `product-screencast` |
| `help-center` | One support question | 30s-3 min | `product-screencast` |
| `release` | One capability, shown | 30s-2 min | `product-screencast` |
| `personalized-sales` | For one account | 1-3 min | `talking-head` |
| `competitive-demo` | Replaces a workflow | 2-4 min | `product-screencast` |
| `webinar-deep-dive` | Complex case, Q&A | 15-30 min | `webinar` |
| `founder-vision` | Why this exists | 1-3 min | `talking-head` |
| `welcome` | What happens next | 60-90s | `talking-head` |
| `social-clip` | One capability | 15-45s | `teaser` |
| `sales-enablement` | One objection | 1-3 min | `explainer` |
| `technical-story` | Technical story beat map | 5-8 min | `product-screencast` |
| `campaign-flagship` | One outcome | 60-70s | `product-screencast` |
| `campaign-comparison` | Sourced before/after | 60-80s | `product-screencast` |
| `campaign-short` | One proof, from a master | 10-20s | `product-screencast` |
| `campaign-outreach` | One audience, one CTA | 70-80s | `product-screencast` |
| `marketing-cutdown` | Feed cut of a master | as briefed | `product-screencast` |

- Buyer-facing: start with the cost, then show config → action → response → result. A settings tour is five films.
- `ai-in-action`, `ai-trust`: show the human change. An instant-perfect result fails.
- `ai-trust`, `technical-story`: `explainer` only when no product can be shown.
- Derivatives: set `sourceJobId`; recut the capture, never re-fake UI.
- A product-demo-studio.config.yaml in a product repository is read-only input. Job config is `job.json` in the external workspace.

## Delivery profiles

`youtube-16x9`, `linkedin`, `presentation`, `webcast` are 1920×1080; `vertical-9x16` 1080×1920; `linkedin-4x5` 1080×1350; `onboarding`, `briefing-board` 1600×1000. All 30 fps. Loudness is `Finish-Media.ps1` two-pass linear I=-16 unless `-Integrated` is passed. Portrait campaigns declare `sourceRegion` and `captionRegion`; `kit/screencast/campaign-contract.mjs` holds the safe areas.

## Series

The series repository holds bible, casts and media, never AgentHub. Same crew: script, scenes, then `generate`, `compose`, `review`.

- Every beat is tagged `FACT`, `DRAMATIZED` or `COMPOSITE`, with a source.
- Episode: cold open, objective, complication, midpoint reversal, climax on a fact, takeaway.
- Validate `schemas/series/`: `episode`, `scene-plan`, `receipt-ledger`, `continuity`. Flag contradictions in character knowledge, system state, timeline.
- Fictionalize first (`sarosh:write`).

## Campaigns

One brief, one brand kit, one lane per asset. Claims need hashed evidence.

| Asset | Lane |
| --- | --- |
| Product evidence | `capture` skill |
| 15-30s ads | `kit/marketing` |
| Films | this crew |
| Speech | `generate` skill |
| Cards, thumbnails | Canva, never film frames |
| PDFs, resizes | Adobe |

Write the script once and derive cuts. Capture once at each ratio's `captureViewports`. A campaign child with `sourceJobId` needs `campaign.derivative`. A connector resize re-runs `validate-picture-integrity.mjs`. Write `campaign-manifest.json` and `qa/campaign-run.json`. Publishing and paid generation need approval.
