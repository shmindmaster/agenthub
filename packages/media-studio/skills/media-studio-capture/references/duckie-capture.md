# Duckie capture operator notes (production and the Zendesk partner sandbox)

Product-specific capture knowledge for Duckie. Identifiers only: no credentials, tokens or customer data belong here. The product repository (`C:\Repos\musa-dev-team\duckie-app`) is read-only input. Every override, storage state and clip lives in the external job workspace.

**The local production simulator (prod-sim) and its fake Zendesk lab were retired on 2026-10-02 and deleted from this machine.** Do not rebuild them, and do not restore a local copy of customer data. Owner direction: films use one of two sources.

## 1. The two sources

| Source | What it shows | Use it for |
| --- | --- | --- |
| **Duckie production** (`app.useduckie.ai`) | Real customer tenants (AvantStay, Mudflap and others) on the deployed code | Read-only story beats: run history, configuration, analytics. Never click a control that writes. |
| **Zendesk partner sandbox** `d3v-duckie-89340.zendesk.com`, connected to the production `Duckie` tenant (`ebdefdd2-7bee-4be6-be0c-87162be9a5d0`) | Duckie working live tickets end to end | Any beat that needs a ticket to arrive, a run to happen and a reply to land |

- The sandbox is Zendesk Suite Enterprise + AI Agents Advanced + Copilot, 5 seats, sponsored for building, testing and demos only. Live support on it gets it suspended.
- Customer setups are simulated as brands in the sandbox. Each brand carries the customer's own groups, fields, tags, forms and triggers, read GET-only from that customer's Zendesk, with fictional tickets and requesters. The sandbox is shared with Amitoj and Justin, so never put real customer tickets or PII in it. Never write to a customer Zendesk.
- Local dev (`docker-compose.dev.yml` + local Supabase `duckie-local` + the `Duckie ngrok` tunnel `duckie-sarosh.ngrok.app` → :3000) connects to an Enterprise sandbox of the account, never to the main account. That way local and production never both reply to one ticket.
- `duckiesupport.zendesk.com` is Duckie's older shared demo Zendesk and is not ours to film or reconfigure.

## 2. Sign-in for capture

- Production: the recorder still has no approved sign-in route. Do not copy cookies or a Chrome profile from a signed-in session. See `mudflap-production-capture-20261001/CAPTURE-READINESS.md` for the open gate.
- Local dev stack: `GET /api/dev-login` signs in as the `DEV_LOGIN_*` test user in `.env.local` (localhost only). Save the resulting storage state in the job workspace.
- To read a run on camera, click a **step row in the run drawer** to open the `Step N of M` modal and advance with **Next**. Mouse-wheel scrolling in a modal only works with the pointer over it.

## 3. Cost and side effects

- Every run is a paid model call. Plan takes; do not loop runs to warm up a scene.
- A sandbox ticket is created through the Zendesk API (`POST /api/v2/tickets.json`) with the sandbox token from `.env.local`. Duckie then receives the webhook. Name the brand and the ticket in the manifest.
- Production tenants are read-only on camera. A beat that would need a write is filmed on the sandbox instead.

## 4. The kit recording lane (2026-09-15)

The wave-1 recut of the Duckie series shipped screenshots looped under narration (one held for 100 s) because the job kit had a still-plate path (`capture-static.mjs`, now deleted) and never called `validate-product-picture.mjs`. The lane that satisfies `product-picture.md` on this product lives in the runtime kit, `%LOCALAPPDATA%\AgentHub\media-studio\_shared\capture-lib\` (not git):

- `record-job.mjs <jobRoot> [S05 …]` records one Playwright take per screen beat from `<jobRoot>/capture/scenes.mjs` (1600×1000 @2×, trace + WebM) and finishes it with `playwright-recast` (cursor approach, click ripple, punch-in). Output: `capture/clips/<id>.webm`, `capture/beats/<id>.json`, `capture/recordings.json` (take length vs narration length; a take under 0.7× is flagged `short`). A Recast failure retries without autoZoom, then keeps the raw WebM with `recast: "fallback"` written down.
- `sim-helpers.mjs` holds the shared Duckie interactions (`go`, `hoverHold`, `pointAt`, `approachAndClick`, `typeText`, `search`, `openAgent`, `pickModel`, `saveDialog`, `dialog`, `dialogScroll`, `cancel`, `smoothScroll`, `hold`), paced to the PDS guide.
- `_shared/tools/build-manifest.py` exits 1 on a screen scene with only a PNG or no clip; `run-job-pipeline.sh` runs `validate-product-picture.mjs` after the manifest and fails a product-screencast whose longest static run exceeds 10 s; the delivery queue runs the validator again before `deliver`.
- Callouts: `capture/callouts/<scene>.json` (`layers[]` with `from`, `to`, `boxes`, `arrows`, `notes`, `dim`, frame pixels) render through `render-overlay.mjs` and apply as time-windowed overlays; the as-of chip follows the storyboard's `asOfChip`.
- Session: `_capture/state.json` from `mint-session.mjs`; when a route bounces to `/login`, re-mint before the first take. `diagnostic-screens.mjs` (route screenshots) is for posters and locator checks only.

## 5. Final check

- [ ] Source named per beat: production (read-only) or the sandbox
- [ ] Storage state from an approved sign-in route, not typed credentials or a copied profile
- [ ] No real customer ticket or PII placed in the sandbox
- [ ] Runs and model cost for the session noted in the job
