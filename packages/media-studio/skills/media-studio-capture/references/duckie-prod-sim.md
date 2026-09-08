# Duckie prod-sim operator notes (recording and read-only investigation)

Product-specific capture knowledge for the Duckie local production simulator. Identifiers only — no credentials, tokens, or customer data belong here. The product repository (`C:\Repos\musa-dev-team\duckie-app`) is read-only input; every override, patch, storage state, and clip lives in the external job workspace.

## 1. Sign-in and navigation for capture

- Sign-in is a GET, no password typing: `GET /api/local-validation/sign-in?actor=<actor>` on the local web app produces a Playwright storage state. Save it in the external workspace and reuse it per persona.
- To read a run on camera, click a **step row in the run drawer** to open the `Step N of M` modal and advance with its **Next** button. Do not scroll the step list; the modal gives one legible step per beat.
- Mouse-wheel scrolling inside a modal only scrolls when the pointer is over the modal. Move the pointer first, then scroll.

## 2. Eval Mode and the egress override

- The release-validation overlay patch (`%LOCALAPPDATA%\AgentHub\runtime\duckie-release-validation-20260907\local-runtime-overlay.patch`) forces **Eval Mode** in `tool-service` whenever `DUCKIE_PROD_SIM_EGRESS_MODE=simulator`. In that state every app, custom, and MCP tool on an ordinary run is refused with `Eval Mode metadata missing required field(s)`.
- Recording fix: a compose overlay that **blanks `DUCKIE_PROD_SIM_EGRESS_MODE` on `tool-service` only** (pattern: `%LOCALAPPDATA%\AgentHub\media-studio\duckie-series-20260908\env\series.override.yml`). App tools then take their normal path — Zendesk through the integration runtime to the local Zendesk simulator. Revert by restarting without the override file.
- The `model-egress-proxy` allowlist (squid) admits **model hosts only**, so customer APIs fail safely even with the override in place. Do not widen it for a recording.

## 3. Cost and side effects

- Every sim run is a **paid model call**. Plan takes; do not loop runs to "warm up" a scene.
- AvantStay scheduler deployments fire **several runs per hour** while active. Disable or pause them before a recording session, and account for their runs when reading cost or run lists.
- Zendesk sim admin API: `http://127.0.0.1:8090/admin/tickets`. `POST` creates a ticket and emits the webhook. Classifier timers can add **late tags** — wait for them or capture before they land, deliberately, and say which in the manifest.

## 4. Supabase project map (identifiers, no secrets)

| Role | Org | Project | Ref | Region |
| --- | --- | --- | --- | --- |
| Production (current, v2) | Duckie | `prod-v2` | `omeohnmqrlijwxuqklsk` | us-west-2 |
| Production (old, v1) | Duckie | `prod` | `fmalpyoztdezbcrvgznn` | — |
| Sarosh dev | dev org | `sarosh-v2` | `mcqwxauowdmbryeledpg` | — |

- Read-only production SQL goes through `duckie-app/investigations/sql/sq-prod-ro.sh` (Management API, `READ ONLY` transaction) or `pnpm db:query --env production --force`. Nothing else writes or reads prod from an agent.
- Targeted local sync follows the deep-dive `env/sync_org.py` pattern (one org, explicit tables) rather than a full dump.
- The claude.ai Supabase connector is signed into a **different account**; do not rely on it for Duckie.

## 5. Final check

- [ ] Storage state came from the sign-in endpoint, not typed credentials
- [ ] Override file is in the external workspace and reverted after the session
- [ ] Schedulers paused; run count and cost noted in the job
- [ ] No production data on screen; synthetic tickets via the sim admin API
