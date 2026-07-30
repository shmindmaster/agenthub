---
name: product-demo-studio-capture
description: >
  Capture and diagnose real product states through deterministic browser automation for any
  repository. Use for screen capture, walkthrough recording, demo-worthiness evidence, screenshots,
  or any product-UI plate used by Remotion. Distinguish capture-fixable roughness from product-fix-
  required UX defects before master capture; use only real workflows and coherent synthetic data,
  and preserve reproducible geometry, timing, error, reset, and deployment evidence.
---

## Discover before capturing

Read the target repository's own instructions and existing test/capture setup first. Reuse its
browser test runner, authentication test path, seed fixtures, reset mechanism, network stubs, and
artifact directory — do not introduce a second capture harness alongside a working one. Never
assume a particular identity provider, framework, or auth pattern; confirm it from the repo itself.
Treat manual browser exploration (the agent's native Browser/Chrome tools) as discovery only — the
canonical screenshot or recording must come from a checked-in or otherwise versioned automation
command (Playwright or the repo's equivalent), so it is reproducible.

When the shared Browser Quality Toolkit is installed, use its `browser-debugging` skill and Chrome
DevTools MCP for live DOM/accessibility, console, network, Lighthouse, and performance evidence.
Connect only to the dedicated QA Chrome endpoint. A shared browser permits one interactive agent at
a time; concurrent agents require separate profiles, ports, synthetic identities, and seed
namespaces. The developer's normal Chrome instance is never an acceptable capture target.

Resolve `PRODUCT_DEMO_STUDIO_ROOT` through the router skill before invoking bundled scripts; do not
assume a Claude-specific plugin-root variable exists on every coding-agent host.

## Walk the workflow before master capture

Require the validated Product Experience handoff for the current repository revision before this
stage. A missing, stale, `REMEDIABLE`, or `DEFERRED` handoff is a stop condition, not an invitation
to conceal product roughness through camera treatment. Product Demo Studio still reruns its own
eleven-item gate to catch capture-specific failures.

Assess every candidate against the eleven-criterion demo-worthiness rubric in
`product-demo-studio/references/killer-demo-playbook.md`. A diagnostic sample may be
captured to classify an ambiguous defect. Record frames, console/network evidence, reset results,
and measured time-to-value in the configured `<WORK_DIR>/feedback/` folder.

- Proceed to master capture for `PASS` episodes.
- Proceed for `CONDITIONAL` episodes only with explicit capture treatments in the manifest.
- Stop master capture for `FAIL` episodes. Preserve only the evidence needed for a buildable UX
  report; editing must not be used to disguise a product-fix-required defect.

## Capture the real product, never a mock

Every capture must be the real, production-capable frontend/backend/database/APIs/permissions
running against a real deployment as an authenticated (synthetic) persona. Do not:

- build a mocked product screen, hard-code a result, or stub the response just to make a beat look good;
- record only-for-the-camera logic, simulate success, or edit a capture to conceal broken behavior;
- let generated imagery invent product UI, text, numbers, tables, or formulas — use a real screenshot
  for a real feature (see `product-demo-studio-remotion`).

If a workflow can't be shown truthfully because the product isn't there yet, fix the product surface
or cut the beat — never fake it. A hard-skipped acceptance test is evidence of unfinished product
work, not a passing capture.

## Fixed, repeatable capture

Use fixed viewports so every capture is pixel-comparable across runs, e.g.:

```json
{
  "viewports": {
    "desktop": { "width": 1440, "height": 1000 },
    "socialVertical": { "width": 390, "height": 844 }
  }
}
```

Do not confuse **capture viewport** (the browser window size you screenshot) with **output video
format** (the final render's width/height, e.g. 1920x1080 / 1080x1920 / 1080x1080 — see
`product-demo-studio-render`). They are independent; a desktop-viewport capture can end up in a
vertical-format render as a cropped/composited plate.

Always force reduced motion so animations/transitions in the live app don't introduce
non-deterministic frames into a screenshot or recording:

```ts
await page.emulateMedia({ reducedMotion: "reduce" });
```

Pin the **locale and timezone** too, so dates, times, and number formatting are identical every run
(a floating timezone silently changes a visible timestamp between takes):

```ts
const context = await browser.newContext({ locale: "en-US", timezoneId: "America/Chicago" });
```

Use a **fresh, clean browser context per take** — no reused profile, no saved autofill, no personal
accounts, no unrelated tabs, and no browser/OS notifications on screen. Combined with a fresh
role-appropriate login and freshly reseeded data (below), every take starts from the same known
state.

Assert on console errors and failed requests during capture — a capture run that silently hit a JS
error or a 500 is not usable footage even if the screenshot looks fine.

## Maximize useful screen space

Default to a clean page-only Playwright capture. If native browser recording is required, use
fullscreen/presentation mode and remove the address bar, tabs, bookmarks, download shelves, OS
taskbar, notifications, unrelated windows, and empty desktop. Browser or OS chrome may appear only
when it is material evidence and the beat is explicitly classified `intentional-context`.

- Use the product's real collapse/hide controls for irrelevant sidebars, filters, help panels, or
  navigation. Never inject CSS or mutate the DOM solely to make the product look cleaner.
- Preserve enough product context that the viewer understands location and cause/effect, but do not
  spend pixels on navigation that is irrelevant to the current beat.
- Plan the delivered frame—not merely the raw viewport. After the declared crop, push-in, or
  recomposition, the active product region must occupy at least half of the usable frame and pass a
  legibility check at the smallest requested output.
- Keep captions, callouts, and the parked cursor outside the active and protected regions. If a
  wide screen cannot remain legible in a vertical or square cut, recompose it around the active
  control/result; do not mechanically shrink the whole desktop.
- Treat app/browser zoom as product state. Prefer 100% browser zoom and composition-level
  reframing. If a legitimate in-product density or zoom control is needed, record it in the
  manifest and verify that it does not misrepresent normal use.

Every manifest declares `captureSurface.mode`, `extraneousChrome`, `irrelevantNavigation`,
`plannedTreatment`, `plannedActiveRegionCoverage`, and `deliveryLegibility`. The validator rejects
coverage below `0.5` and any non-passing delivery legibility result.

## Capture manifest

For every captured beat, record: scenario ID, product version/source commit, fixture/seed version,
environment, **deployment identity and its verification state** (the exact deployment you captured,
confirmed at capture time — not assumed), persona/workspace, route, viewport, device scale factor,
locale/timezone, timestamp, action, target selector, focus bounding box, secondary protected
regions, capture-surface/screen-space treatment, cursor start/destination/park points and duration,
visible click cue, action/result/narration offsets, screenshot and/or video path, console errors, failed requests,
**missed visual targets** (an expected element/text that didn't appear), reset result, readiness
state, and an **explicit pass/fail verdict** for the beat. Obtain focus rectangles from the browser
(`getBoundingClientRect()` or Playwright's `boundingBox()`) rather than guessing camera coordinates
by eye.

**Any material capture fault blocks rendering** — a console error, a failed request, a missed target,
a wrong deployment, or a `fail` verdict means the beat is re-captured, not composited into a master.

```json
{
  "scenario": "workflow-example",
  "beat": "review-result",
  "route": "/example/workflow",
  "focus": { "x": 1180, "y": 240, "width": 520, "height": 420 },
  "protectedRegions": [{ "x": 900, "y": 160, "width": 850, "height": 700 }],
  "captureSurface": {
    "mode": "page-only",
    "extraneousChrome": "none",
    "irrelevantNavigation": "collapsed",
    "plannedTreatment": "push-in",
    "plannedActiveRegionCoverage": 0.68,
    "deliveryLegibility": "pass"
  },
  "interaction": {
    "kind": "click",
    "target": "button[data-demo='review-exception']",
    "cursor": {
      "from": [1450, 780],
      "to": [1520, 430],
      "park": [1760, 930],
      "durationMs": 700
    },
    "cue": "visual",
    "narrationSync": {
      "cursorLeadSeconds": 0.35,
      "actionAtSeconds": 1.1,
      "resultVisibleAtSeconds": 1.8,
      "spokenResultAtSeconds": 2.0
    }
  },
  "viewport": { "width": 1920, "height": 1080, "deviceScaleFactor": 2 }
}
```

Validate a manifest with `scripts/validate-capture-manifest.mjs` before treating it as complete:

```bash
node "${PRODUCT_DEMO_STUDIO_ROOT}/scripts/validate-capture-manifest.mjs" <path-to-manifest.json>
```

This is the geometry `product-demo-studio-remotion`'s overlay-placement rule and
`compute-overlay-placement.mjs` consume — capture it accurately or every downstream zoom/callout
placement decision inherits the error.

## Auth and environments: discover first, never real credentials

Use only local, preview, staging, or explicitly authorized synthetic hosted environments. Read the
target repo's own auth-testing convention rather than assuming one — e.g. one observed repo signs
in via `@clerk/testing/playwright` (`clerkSetup()`, `clerk.signIn({ emailAddress })`) against
gitignored storage state; another uses its own JWT-based test-identity flow. Whatever the
mechanism, **never** type, store, display, or record a real or long-lived password, token, or
credential into the product's own login field for capture purposes — use the repo's approved test
ticket, storage state, or local auth stub. A local auth stub is fine for smoke checks, but its
captures are never release evidence — record which one was used and let the readiness state reflect
that.

## Seeded data only

Capture against seeded/synthetic demo data exclusively. Never capture a screen containing a real
customer, patient, vendor, invoice, route, account, or dollar figure — even accidentally, e.g. by
capturing a shared staging environment that still has old real records in it.

**Reset and reseed before every episode or take**, so each take starts from the same known state and
no beat depends on an accidental side effect left by a previous one. Where a capture mutates state,
verify isolation, record the before state, run the scenario, capture the result, reset, and record
reset evidence — don't leave a demo tenant in a dirty state.

Seed a coherent mini-story rather than random rows: one humanized persona, a believable hard case,
and specific synthetic values that make the before-state cost and payoff legible. Label synthetic
figures and verify every visible value against the episode truth sheet. For problem-solving or AI
episodes, capture a brief taste of the difficult input before the clean result and keep the visible
reasoning/human-control moment truthful.

## Capture for story, not just coverage

- Start on the declared cold-open frame, never a login sequence or dashboard tour.
- Hold the shown before-state for roughly three to five seconds.
- Capture the single hero reveal with enough clean lead-in and tail for pre-silence, push-in, one
  restrained cue, and a readable result hold.
- Keep spatial continuity. The final product interaction must feel like a skilled person is actually
  using it: ease the cursor from a known location, hover briefly when useful, click/type/scroll on
  the real control, show the resulting state change, then park away from content. No jitter,
  unexplained teleporting, meaningless circles, or cursor motion over a static state.
- Record actual Playwright actions for interactive beats. A programmatically rendered pointer is
  acceptable only when it reproduces the manifest's real action path and exact state transition;
  it must not imply a click or result that the capture evidence does not contain.
- Give clicks a visible cue; use at most one restrained audio cue at the protected hero moment.
  Keep cursor movement roughly 200–2,500 ms and let it lead the action by no more than 1.5 seconds.
- Align to narration explicitly: the cursor leads the eye, the action happens, the result becomes
  visible, and the spoken result follows. Do not make narration announce a state that has not yet
  appeared.
- Record enough handles for speed ramps and attention resets, but never speed or cut away a product
  wait whose missing feedback is itself a product-fix-required defect.

## Manifest shapes are repo-specific — discover, don't force

Different repos solve "how do I drive the capture" differently, and that's fine — don't force a
migration between them without being asked. Two patterns seen in practice:

1. **Static manifest + single runner** — a `capture-manifest.json` listing `{ id, path, auth,
   persona }` routes, run once per route by one Playwright spec.
2. **Spec-per-flow** — a native Playwright spec per user flow, with helper modules for the capture
   plan and persona login, driven by env vars, and mutating (data-writing) steps gated behind an
   explicit opt-in env flag.

A repo with no existing convention: prefer pattern 2 — it composes better with a real E2E suite and
CI, and keeps mutating captures opt-in by default.

## Output location

Write raw captures to the repository's existing gitignored media-work directory if one exists
(e.g. `_production/capture/`). If none exists, use a gitignored `media/captures/raw/` directory.
Never commit raw screen recordings or screenshots to git — commit the reproducibility scripts and
manifests, not the large raw media. Follow the repository's own storage policy for anything that
needs to live outside git (large masters, review queues); this plugin does not assume or require
any particular external storage location.

## Redaction rules for what the capture may show

- Never show a third-party portal, login, private URL, secret, or live external workflow unless it
  is explicitly authorized and entirely synthetic.
- Never show real names, tenant/account/route IDs, or dollar amounts unless explicitly synthetic
  and clearly recognizable as demo data.
- Never show unapproved comparative claims, rankings, or third-party scoring.
- No secrets, tokens, or API keys visible in any URL bar, devtools panel, or config screen.

## Before this capture is usable externally

A capture is not release evidence just because it exists and looks clean. It still needs a
release-evidence manifest entry (`classification`, `reviewedBy`) via `product-demo-studio-render`'s
evidence gate before it is dropped into a Remotion `public/` folder for a shared/marketing render,
imported into Descript, or referenced anywhere external. Internal proxy iteration does not need
this gate — see the evidence-redaction rule in the router skill for exactly where the boundary is.
