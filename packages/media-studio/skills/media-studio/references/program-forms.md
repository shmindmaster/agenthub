# Program forms

Set `programForm` on `job.json` when the job is a buyer-library or named format. Infer it from the brief. Then pick `kind` from the table. One film, **one promise**. Organize around the viewer's job, not the product nav.

Do not invent metrics, customer names, or AI behavior. Unsourced numbers are omitted.

## Production kinds (how it is made)

| Kind | Use | Default profile | Notes |
| --- | --- | --- | --- |
| `product-screencast` | Real UI, cursor, zoom | Recast + product-picture | Outcome-first. No feature tour. |
| `briefing` | Argument on the archetype kit | `briefing-board` | Not a webcast. |
| `training` | One skill per clip | `onboarding` | ≤ ~3 min unless the user asked longer. |
| `explainer` | Idea, no live product required | `youtube-16x9` | `story-craft.md` spine. |
| `talking-head` | Face must carry the line | `youtube-16x9` | Lower-third + headroom. |
| `animation` | Motion itself teaches | `youtube-16x9` | |
| `audio-only` | Voice/bed only | n/a | |
| `series-episode` | Series methodology | `youtube-16x9` | |
| `webcast` | One-to-many broadcast feel | `webcast` | Lower-thirds, chapters, speaker+slide layouts. Passive audience. |
| `webinar` | Taught session + Q&A chapters | `webcast` | Interactive structure even if recorded. |
| `keynote` | Speaker-led argument | `youtube-16x9` | Angle changes; not a single locked webcam. |
| `documentary` | Picture-led | `youtube-16x9` | Slower VO; silence for image. |
| `teaser` | 15–45s hook only | `vertical-9x16` or `linkedin` | No intro, no denouement. |

## Library forms (what the viewer came for)

| `programForm` | Promise | Length | Default `kind` |
| --- | --- | --- | --- |
| `hero` | Problem → solution → result | 30–60s | `product-screencast` recut, or `teaser` from that capture |
| `product-overview` | Real product, major workflows | 2–5 min | `product-screencast` |
| `outcome-workflow` | Pain → task → AI does it → human reviews → result | 1–3 min | `product-screencast` |
| `role-demo` | One persona's job only | 2–5 min | `product-screencast` |
| `feature-tutorial` | One task, named as an outcome | 1–3 min | `product-screencast` |
| `customer-story` | Problem → workflow → evidence → what changed | 2–5 min | `documentary` + capture plates |
| `before-after` | Old steps vs new path | 30–90s | `product-screencast` |
| `ai-in-action` | Input → draft → concern → edit → save | 1–3 min | `product-screencast` |
| `ai-trust` | Data in, controls, accuracy limits, human approval, what it cannot do | 2–5 min | `product-screencast` for UI claims; `explainer` only when no product can be shown |
| `integration-demo` | This product with that system | 1–3 min | `product-screencast` |
| `onboarding` | First successful outcome | 2–5 min | `product-screencast` |
| `help-center` | One support question | 30s–3 min | `product-screencast` |
| `release` | One new capability, shown | 30s–2 min | `product-screencast` or `teaser` recut from capture |
| `personalized-sales` | Recorded for one account | 1–3 min | `talking-head` + capture |
| `competitive-demo` | Replaces the current workflow | 2–4 min | `product-screencast` |
| `webinar-deep-dive` | Complex case, chapters, Q&A | 15–30 min | `webinar` |
| `founder-vision` | Why this exists | 1–3 min | `talking-head` |
| `welcome` | Human welcome + what happens next | 60–90s | `talking-head` |
| `social-clip` | One striking capability | 15–45s | `teaser` |
| `sales-enablement` | One objection (security, implementation, ROI) | 1–3 min | `explainer` or `product-screencast` |
| `technical-story` | What changed → why → where it happens → why it matters; evidence serves the story (`technical-story.md`) | 5–8 min | `product-screencast` (or `explainer` when no product can be shown) |
| `campaign-flagship` | One product outcome, full action and result | 60–70s | `product-screencast` |
| `campaign-comparison` | A sourced before/after workflow comparison | 60–80s | `product-screencast` |
| `campaign-short` | One proof moment cut from a locked master | 10–20s | `product-screencast` |
| `campaign-outreach` | One audience-specific outcome and CTA | 70–80s | `product-screencast` |

## Formulas (do not skip)

**Outcome-workflow / role-demo / product-overview / feature-tutorial / onboarding / help-center (buyer-facing):** start with the cost, then **show** the work (`product-picture.md`): config that drives it → action → response → result. Real UI + cursor + zoom. Not an avatar on fake chrome, Ken Burns, or a nav tour.

**AI-in-action / ai-trust:** show control. Input → draft → review → highlighted concern → human change → save. Instant-perfect-result is a fail.

**Customer-story:** customer speaks → their problem on screen → the workflow → a **sourced** result on type → what that meant. Not a talking-head “we love it.”

**Technical-story:** hook on the problem (not the UI) → real scenario with synthetic data → the weird behavior → what is actually happening (flow overlay) → code reveal, 5–20 lines, one highlight at a time → fix before/after → replay → what this means. Mini technical documentary, not a tutorial. Full rules in `technical-story.md`.

**One promise:** a settings tour is five films, not one 16-minute clip.

**Derivatives:** one locked master may cut to shorter forms. Set `sourceJobId` on the child job. Do not re-fake product UI for a social clip — recut the capture.

**Campaign forms:** use the same product-screencast capture and encoded gates. Set an explicit `deliveryProfile`: `youtube-16x9` (1920×1080), `vertical-9x16` (1080×1920), or `linkedin-4x5` (1080×1350). Portrait clips declare a bounded `sourceRegion` in the capture manifest to frame the relevant UI intentionally; the encoded gate matches the same crop to the receipt-bound source. Graphics and portrait captions live in declared safe regions, clear of visible controls. `job.campaign` records either one scenario and record across the film or separately labeled vignettes, every dated claim with a hashed evidence file, and every media asset with origin and rights. A child job also records `sourceJobId`, the exact parent candidate hash, and hashes of reused source assets. Use `story/timed-graphics.json` for timed PNG overlays and review their timing and visible controls on the encoded candidate. A vignette label must cover each assigned segment's opening and never overlap another vignette. The contract is executable in `kit/screencast/campaign-contract.mjs` and `scripts/validate-viewer-release.mjs`.

**Refuse:** feature-tour openings, logo intros, menu walkthroughs, hiding AI mistakes, invented proof.
