# Campaigns (multi-asset production)

A launch, social pack, sales kit, event kit, brand variant set, customer-story package or demo series is one
campaign: several assets from one brief, one brand kit and one set of approved claims. This reference replaces the
retired `portfolio-campaign-production` skill and the Notion Prompt OS routing it depended on. The Prompt OS is an
archived reference (its records stopped being maintained in August 2026 and its own start page says so); nothing
routes to it, no workflow body is fetched from it, and no run is logged there.

## Inputs, from the product itself

- **Brand kit**: colours, type, logo lockups, end-card and CTA treatment, from the product repository's design
  tokens or its documented brand kit. A connector brand kit (Canva, Adobe) is a projection of that source, never
  the authority.
- **Approved claims**: only claims the product's own evidence supports (`job.campaign.claims` with hashed evidence,
  as `validate-viewer-release.mjs` checks for campaign forms). No invented metrics, testimonials or customer names.
- **Restricted data and legal footer**: the product's declared rules travel with every asset; synthetic data is
  disclosed on screen (`story-craft.md` → "No fluff").
- **Product state**: a running product is captured, never redrawn (`product-picture.md`); product changes found
  on the way are Product-Readiness Feedback for a separate engineering task.

## Lanes (one owner each; never two lanes for one deliverable)

| Asset | Lane | Owner |
| --- | --- | --- |
| Product evidence (screens, flows, receipts) | Playwright capture + Recast | `media-studio-capture` |
| 15–30 s ads in 16:9 / 4:5 / 9:16 | `kit/marketing` (mvg): lint → voice → timing → assets → capture reuse → compose → QA → deliver | `media-studio` (marketing cut, `marketing-readiness.md`) |
| Films, explainers, technical stories, series episodes | this studio's crew (`writer.md` → `storyboard.md` → `visuals.md` → `direction.md` → generate → compose → qa) | `media-studio` |
| Programmatic motion, cards, kinetic type | Remotion archetype kit | `media-studio-compose` |
| Spoken-content finishing (transcript edits, filler removal, share links) | Descript, optional | `media-studio-compose/references/descript.md` |
| Static multi-format social cards, thumbnails, brand-kit layouts | Canva connector (never film frames) | registry `native-connectors.json` → `canva` |
| PDF one-pagers, font kits, social resize of **delivered** masters, Firefly stills under the abstract-imagery rule | Adobe connector | registry `native-connectors.json` → `adobe` |
| Speech, SFX, music beds on the governed ledger | `elevenlabs` skill (CLI), Local-AI first | `elevenlabs`, `local-ai-stack` |
| Release gates on every asset | `media-studio-qa` | `media-studio-qa` |

Pick the lane by the asset, not by the tool that happens to be open. A lane the registry records as `false`
(checked-absent) is unowned: say so and hand the work to a person; do not substitute a general-purpose tool and
present the result as that lane.

## Plan

1. Name the campaign, the audience, the one promise, and the asset list with ratio, length and destination per asset.
2. Write the shared script once (`writer.md`); derive per-asset cuts from it. One idea said once across the
   campaign too: a card that repeats the film's line is cut.
3. Capture product evidence once at every delivered ratio's own viewport (`media-studio-capture` §2b); every asset
   draws from those receipts.
4. Produce per lane. Every asset gets the gates its kind requires; marketing cuts pass the marketing floor.
5. Deliver under `F:\My Drive\Videos\<Product>` for film (`NN - Title.mp4`, README index) and the product's
   documented asset folders for the rest; the registry's `product-video-delivery.json` names the review roots.

## Output contract

- A campaign folder in the external job workspace with every deliverable.
- `campaign-manifest.json`: per asset `{ id, type, lane, ratio, durationSeconds, source: { receipts, claims }, output: { path, sha256 }, gates: { ... }, approvedBy }`.
- A run record in the job workspace (`qa/campaign-run.json`): who, when, spend per lane against the shared
  ledger, what was delivered, what was not and why. Nothing is published, posted or sent from this studio.

## Gates that apply to every asset

- Brand assets, live product data and customer material are sensitive; approved sources only.
- Approval before any outward-facing publish and before paid render or generation spend (the shared ElevenLabs
  ledger, Adobe or Canva credits).
- Never copy privileged, legal or discovery media into a creative pipeline.
- A delivered master that is later resized or recut by a connector is a derivative: it carries the parent's hash and
  passes `validate-picture-integrity.mjs` again (no upscale, no crop that removes UI, no bars).
