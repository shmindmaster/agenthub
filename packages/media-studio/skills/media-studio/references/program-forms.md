# Program forms

Set `programForm` on `job.json` when the job is a buyer-library or named format. Infer it from the brief. Then pick `kind` from the table. One film, **one promise**. Organize around the viewer's job, not the product nav.

Do not invent metrics, customer names, or AI behavior. Unsourced numbers are omitted.

## Production kinds (how it is made)

| Kind | Use | Default profile | Notes |
| --- | --- | --- | --- |
| `product-screencast` | Real UI, cursor, zoom | PDS | Outcome-first. No feature tour. |
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

## Formulas (do not skip)

**Outcome-workflow / role-demo / product-overview / feature-tutorial / onboarding / help-center (buyer-facing):** start with the cost, then **show** the work. Real UI + cursor + zoom + visible result (`product-picture.md`). Occasional presenter. Not an AI avatar walking a fake dashboard. Not Ken Burns on a screenshot. Not “Welcome to Acme, on the left is the nav.”

**AI-in-action / ai-trust:** show control. Input → draft → review → highlighted concern → human change → save. Instant-perfect-result is a fail.

**Customer-story:** customer speaks → their problem on screen → the workflow → a **sourced** result on type → what that meant. Not a talking-head “we love it.”

**Technical-story:** hook on the problem (not the UI) → real scenario with synthetic data → the weird behavior → what is actually happening (flow overlay) → code reveal, 5–20 lines, one highlight at a time → fix before/after → replay → what this means. Mini technical documentary, not a tutorial. Full rules in `technical-story.md`.

**One promise:** a settings tour is five films, not one 16-minute clip.

**Derivatives:** one locked master may cut to shorter forms. Set `sourceJobId` on the child job. Do not re-fake product UI for a social clip — recut the capture.

**Refuse:** feature-tour openings, logo intros, menu walkthroughs, hiding AI mistakes, invented proof.
