---
name: capture
description: Produces hash-bound WebM takes of a live product with Recast pointer, click and zoom finishing. Use when a film needs real product footage, a screen recording, a Playwright take or a re-record of a beat. Not for stills or slides; use generate or compose.
---

# Capture

## Workflow contract

1. Use the approved picture plan, authorized synthetic target, and locked lines or voice timing when required.
2. Run browser and capture preflight, then record each approved beat and verify the observed action against the planned result.
3. Hand `compose` the clips, per-beat evidence, recordings manifest and hash-bound receipt.
4. If preflight or evidence fails, keep the previous accepted take and record a new candidate only for the failed beat.

Read the contract `../video/references/product-picture.md` first. Screen beats are real WebM plus Recast. PNGs are posters only, never the picture of a `screen` beat, even when a take is late.

Work only in the external job workspace, because the product repository is read-only. Scripts, traces, recordings, manifests, auth state and reset evidence all stay there. Never add a capture test, helper or file to the product repo. A needed product or seed change is readiness feedback for a separate task.

Capture only an owner-authorized synthetic tenant or sandbox with fictional data. Never show real customer tickets, names or PII, write to customer systems, or copy cookies or signed-in browser profiles. Production capture needs an approved sign-in route and stays read-only.

## Browser

Deterministic takes are Playwright CLI or Test from the external workspace. Exploratory looks use the running surface's browser where `registry/fleet-profile.json` `hostSurfaces` records `browser.isolated: true`, and happen before the take. Never write a host-specific browser tool name into a storyboard, manifest or script.

## References

- `references/recording.md`: Read when writing `scenes.mjs`, recording multiple ratios or a native mobile app, or hitting Recast limits (`autoZoom`, `.recast-tmp`), uploads, selects or filled inputs.
- `references/abacare-local.md`: Read when capturing ABACare.
- `references/abacare-lexicon.json`: Read when checking ABACare pronunciation.

Read when executing this skill for its detailed commands and gates. [Workflow detail](references/workflow-detail.md)
